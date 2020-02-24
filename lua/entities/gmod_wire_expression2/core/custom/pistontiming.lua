--[[ **************************** CONFIGURATION **************************** ]]

E2Lib.RegisterExtension("pistontiming", true,
  "Allows E2 chips to attach pistons to the engine crankshaft props",
  "Configures prop engine pistons without messy boolean control conditions. Uses dedicated routines for each piston type."
)

-- Client and server have independent value
local gnIndependentUsed = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_PRINTABLEONLY)
-- Server tells the client what value to use
local gnServerControled = bit.bor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_PRINTABLEONLY, FCVAR_REPLICATED)

local gnD2R       = (math.pi / 180)
local gsKey       = "wire_expression2_pistontiming"
local gtChipInfo  = {} -- Stores the global information for every E2
local gtRoutines  = {} -- Stores global piston routines information
local varEnStatus = CreateConVar(gsKey.."_enst",  0, gnIndependentUsed, "Enables status output messages")
local varDefPrint = CreateConVar(gsKey.."_dprn", "TALK", gnServerControled, "FTrace default status output")
local gsFormLogs  = "E2{%s}{%s}:piston: %s" -- Contains the logs format of the addon
local gsDefPrint  = varDefPrint:GetString() -- Default print location
local gtPrintName = {} -- Contains the print location specification
      gtPrintName["NOTIFY" ] = HUD_PRINTNOTIFY
      gtPrintName["CONSOLE"] = HUD_PRINTCONSOLE
      gtPrintName["TALK"   ] = HUD_PRINTTALK
      gtPrintName["CENTER" ] = HUD_PRINTCENTER

--[[ **************************** CALLBACKS **************************** ]]

gsVarName = varDefPrint:GetName()
cvars.RemoveChangeCallback(varDefPrint:GetName(), varDefPrint:GetName().."_call")
cvars.AddChangeCallback(varDefPrint:GetName(), function(sVar, vOld, vNew)
  local sK = tostring(vNew):upper(); if(gtPrintName[sK]) then gsDefPrint = sK end
end, varDefPrint:GetName().."_call")

--[[ **************************** PRIMITIVES **************************** ]]

local function logStatus(sMsg, oSelf, nPos, ...) -- logError
  if(varEnStatus:GetBool()) then
    local nPos = (tonumber(nPos) or gtPrintName[gsDefPrint])
    local oPly, oEnt = oSelf.player, oSelf.entity
    local sNam, sEID = oPly:Nick() , tostring(oEnt:EntIndex())
    local sTxt = gsFormLogs:format(sNam, sEID, tostring(sMsg))
    oPly:PrintMessage(nPos, sTxt:sub(1, 200))
  end; return ...
end

local function isValid(oE)
  return (oE and oE:IsValid())
end

local function getAngNorm(nA)
  return ((nA + 180) % 360 - 180)
end

local function getSign(nN)
  return (((nN > 0) and 1) or ((nN < 0) and -1) or 0)
end

local function getWireXYZ(nX, nY, nZ)
  local x = (tonumber(nX) or 0)
  local y = (tonumber(nY) or 0)
  local z = (tonumber(nZ) or 0)
  return {x, y, z}
end

local function getWireCopy(tV)
  return (tV and table.Copy(tV) or getWireXYZ())
end

local function getWireAbs(tV) local nN = 0
  for iD = 1, 3 do nN = nN + (tonumber(tV[iD]) or 0)^2 end
  return math.sqrt(nN)
end

local function setWireDiv(tV, vN)
  local nN = (tonumber(vN) or getWireAbs(tV))
  for iD = 1, 3 do tV[iD] = (tV[iD] / nN) end; return tV
end

local function setWireXYZ(tV, nX, nY, nZ)
  tV[1] = (tonumber(nX) or 0)
  tV[2] = (tonumber(nY) or 0)
  tV[3] = (tonumber(nZ) or 0); return tV
end

local function isWireZero(tV)
  local bX = ((tonumber(tV[1]) or 0) == 0)
  local bY = ((tonumber(tV[2]) or 0) == 0)
  local bZ = ((tonumber(tV[3]) or 0) == 0)
  return (bX and bY and bZ)
end

--[[ **************************** HELPER **************************** ]]

--[[
Calculates normalized ramp output of the roll marker period
 * nP -> The roll marker period of the marker offset (R - H)
]]
local function getRampNorm(nP)
  local nN = getAngNorm(nP)
  local nA, nM = -getAngNorm(nN + 180), math.abs(nN)
  return (((nM > 90) and nA or nN) / 90)
end

--[[
Calculates vector cross product vua axis and highest point
 * tR -> Wiremod vector type of the roll marker
 * tH -> Wiremod vector type of the highest point
 * tA -> Wiremod vector type of the shaft rotation axis
]]
local gvRoll, gvHigh, gvAxis = Vector(), Vector(), Vector()
local function getWireCross(tR, tH, tA)
  gvRoll:SetUnpacked(unpack(tR)); gvRoll:Normalize()
  gvHigh:SetUnpacked(unpack(tH)) -- Normalized on creation
  gvAxis:SetUnpacked(unpack(tA)) -- Normalized on creation
  return gvHigh:Cross(gvRoll):Dot(gvAxis)
end

--[[
Allocates/Indexes memory location for given expression chip
 * oSelf -> Reference to the current expression chip allocated/indexed
]]
function getExpressionSpot(oSelf)
  local oRefr = oSelf.entity      -- Pick a key reference
  local tSpot = gtChipInfo[oRefr] -- Index the expression spot
  if(not tSpot) then              -- Check expression chip spot
    gtChipInfo[oRefr] = {}        -- Allocate table when not available
    tSpot = gtChipInfo[oRefr]     -- Refer the allocated table to store into
    tSpot.Axis = {0,0,0}          -- Rotation axis stored as a local vector relative to BASE
    tSpot.Mark = {0,0,0}          -- Roll zero-mark stored as a local vector relative to SHAFT
    tSpot.Base = nil              -- Entity for overloading and also the engine BASE entity
  end; return tSpot               -- Return expression chip dedicated spot
end

--[[
Converts the mark vector local to the SHAFT entity to
a mark vector local to the base entity
 * tV -> Mark as regular wire vector data type
 * oE -> The entity used as an engine SHAFT prop
 * oB -> The entity used as an engine BASE prop
]]
local function getMarkBase(tV, oE, oB)
  if(not isValid(oE)) then return getWireXYZ() end
  if(not isValid(oB)) then return getWireXYZ() end
  if(isWireZero(tV)) then return getWireXYZ() end
  local vM = Vector(tV[1], tV[2], tV[3])
  vM:Rotate(oE:GetAngles()); vM:Add(oB:GetPos())
  vM:Set(oB:WorldToLocal(vM))
  return getWireXYZ(vM:Unpack())
end

--[[
Reads the piston data from crankshaft entity placeholder
If the iD is not provided returns all crankshaft modifications
 * oE -> The crankshaft entity to check
 * iD -> The piston data to be checked and returned
]]
local function getData(oE, iD) local tP = oE[gsKey]
  return (tP and (iD and tP[iD] or tP) or nil)
end

--[[
Writes the piston data to crankshaft entity placeholder
If the iD is not provided writes to crankshaft placeholder
 * oE -> The crankshaft entity to be indexed
 * iD -> The piston key to be used for indexing
 * oV -> The value to be written in the placeholder
]]
local function setData(oE, iD, oV)
  if(iD) then oE[gsKey][iD] = oV else oE[gsKey] = oV end
  return oE -- Return crankshaft entity
end

--[[ **************************** PISTON ROUTINES ****************************

 R  -> Roll value of the SHAFT entity
 H  -> Roll value for the piston highest point ( vector or number )
 L  -> Roll value for the piston lowest point ( vector or number )
 M  -> Piston initialization mode for the routine issued by the user
 A  -> Axis issued by the cross product timings in local coordinates
[1] -> Contains the evaluation function definition for the given mode
[2] -> Contains the internal data interpretation type for output calculation

]]

-- Sign mode [nM=1] https://en.wikipedia.org/wiki/Square_wave
gtRoutines[1] = {
function(R, H, L, M, A)
  local nN = getAngNorm(R - H)
  return ((math.abs(nN) == 180) and 0 or getSign(nN))
end, "number" }

-- Wave mode [nM=2] https://en.wikipedia.org/wiki/Sine_wave
gtRoutines[2] = {
function(R, H, L, M, A)
  return math.sin(gnD2R * getAngNorm(R - H))
end, "number" }

-- Cross product wave mode [nM=3] https://en.wikipedia.org/wiki/Sine_wave
gtRoutines[3] = {
function(R, H, L, M, A)
  return getWireCross(R, H, A)
end, "vector" }

-- Cross product sign mode [nM=4] https://en.wikipedia.org/wiki/Square_wave
gtRoutines[4] = {
function(R, H, L, M, A)
  return getSign(getWireCross(R, H, A))
end, "vector" }

-- Direct ramp force mode [nM=5] https://en.wikipedia.org/wiki/Triangle_wave
gtRoutines[5] = {
function(R, H, L, M, A)
  return getRampNorm(R - H)
end, "number" }

-- Trochoid force mode [nM=6] https://en.wikipedia.org/wiki/Trochoid
gtRoutines[6] = {
function(R, H, L, M, A)
  local nP = getAngNorm(R - H)
  local nN = getRampNorm(R - H + 90)
  return getSign(nP) * math.sqrt(1 - nN^2)
end, "number" }


--[[ **************************** WRAPPERS ****************************

 * oS (expression)     --> The instance table of the E2 chip itself
 * oE (entity)         --> Entity of the engine crankshaft. Usually also the engine E2 prop.
 * iD (number, string) --> Key to store the data by. Either string or a number.
 * oT (number, vector) --> Top location of the piston in degrees or
                           local direction vector relative to the BASE prop entity.
 * nM (number)         --> Operational mode on initialization. It chooses between the
                           defined list of algorithms for obtaining the output function
 * oA (vector)         --> Engine rotational axis local direction vector relative to the
                           BASE prop entity used for projections
]]
local function setPistonData(oS, oE, iD, oT, nM, oA)
  if(not isValid(oE)) then return nil end
  local tP, vL, vH, vA = getData(oE); if(not tP) then
    setData(oE, nil, {}); tP = getData(oE) end
  local nM, rT = (tonumber(nM) or 0), nil -- Switch initialization mode
  local tR = gtRoutines[nM]; rT = tostring(tR and tR[2] or "xxx")
  -- Sign [1], sine [2] ramp [5] troc [6] data type (number)
  if(rT == "number") then -- Check number internals
    vH, vL, vA = oT, getAngNorm(oT + 180), nil -- Normalize the high and low angle
  elseif(rT == "vector") then -- Cross product [3], [4] (vector)
    if(isWireZero(oT)) then return logStatus("High ["..nM.."] vector zero", oS) end
    if(isWireZero(oA)) then return logStatus("Axis ["..nM.."] vector zero", oS) end
    vH = setWireDiv({ oT[1], oT[2], oT[3]}) -- Nomalized top vector location
    vL = setWireDiv({-oT[1],-oT[2],-oT[3]}) -- Nomalized bottom vector location
    vA = setWireDiv({ oA[1], oA[2], oA[3]}) -- Nomalized axis vector
  else return logStatus("Mode ["..nM.."]["..rT.."] not supported", oS) end
  return setData(oE, iD, {tR[1], vH, vL, nM, vA})
end

local function getPistonData(oE, iD, vR, iP)
  if(not isValid(oE)) then return 0 end
  local tP = getData(oE, iD); if(not tP) then return 0 end
  if(iP) then return (tP[iP] or 0) end
  return tP[1](vR, tP[2], tP[3], tP[4], tP[5])
end

local function enSetupData(oE, iD, sT)
  if(not isValid(oE)) then return false end
  local nM = getPistonData(oE, iD, nil, 4)
  local tR = gtRoutines[nM] -- Read routine
  return (sT == tostring(tR and tR[2] or "xxx"))
end

--[[ **************************** GLOBALS ( BASE ENTITY ) **************************** ]]

__e2setcost(1)
e2function entity entity:setPistonBase(entity oB)
  if(not isValid(this)) then return nil end
  if(not isValid(oB)) then return nil end
  local tSpot = getExpressionSpot(self)
  tSpot.Base = oB; return this
end

__e2setcost(1)
e2function entity entity:setPistonBase()
  if(not isValid(this)) then return nil end
  local tSpot = getExpressionSpot(self)
  tSpot.Base = this; return this
end

__e2setcost(1)
e2function entity entity:resPistonBase()
  local tSpot = getExpressionSpot(self)
  tSpot.Base  = nil; return this
end

__e2setcost(1)
e2function entity entity:getPistonBase()
  local tSpot = getExpressionSpot(self)
  local oB = tSpot.Base -- Read base entity
  if(isValid(oB)) then return oB end
  return nil -- There is no valid base entity
end

--[[ **************************** BASE AXIS ( GLOBALS ) **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonAxis()
  local tSpot = getExpressionSpot(self)
  return tSpot.Axis
end

__e2setcost(1)
e2function entity entity:resPistonAxis()
  local tSpot = getExpressionSpot(self)
  setWireXYZ(tSpot.Axis, 0, 0, 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(vector vA)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, vA[1], vA[2], vA[3])); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(vector2 vA)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, vA[1], vA[2], 0)); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(array vA)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, vA[1], vA[2], vA[3])); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(number X, number Y, number Z)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, X, Y, Z)); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(number X, number Y)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, X, Y, 0)); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(number X)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, X, 0, 0)); return this
end

--[[ **************************** SHAFT MARK ( GLOBALS ) **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonMark()
  local tSpot = getExpressionSpot(self)
  return tSpot.Mark
end

__e2setcost(1)
e2function entity entity:resPistonMark()
  local tSpot = getExpressionSpot(self)
  setWireXYZ(tSpot.Mark, 0, 0, 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(vector vM)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, vM[1], vM[2], vM[3])); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(vector2 vM)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, vM[1], vM[2], 0)); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(array vM)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, vM[1], vM[2], vM[3])); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(number X, number Y, number Z)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, X, Y, Z)); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(number X, number Y)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, X, Y, 0)); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(number X)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, X, 0, 0)); return this
end

--[[ **************************** SHAFT MARK ( LOCAL ) **************************** ]]

__e2setcost(5)
e2function vector entity:cnvPistonMark(vector vM, entity oB)
  return getMarkBase(vM, this, oB)
end

__e2setcost(6)
e2function vector entity:cnvPistonMark(vector vM)
  local tSpot = getExpressionSpot(self)
  return getMarkBase(vM, this, tSpot.Base)
end

__e2setcost(7)
e2function vector entity:cnvPistonMark(number X, number Y, number Z)
  local tSpot = getExpressionSpot(self)
  return getMarkBase(getWireXYZ(X, Y, Z), this, tSpot.Base)
end

__e2setcost(6)
e2function vector entity:cnvPistonMark(entity oB)
  local tSpot = getExpressionSpot(self)
  return getMarkBase(tSpot.Mark, this, oB)
end

__e2setcost(6)
e2function vector entity:cnvPistonMark()
  local tSpot = getExpressionSpot(self)
  return getMarkBase(tSpot.Mark, this, tSpot.Base)
end

--[[ **************************** CREATE **************************** ]]

__e2setcost(20)
e2function entity entity:setPistonSign(number iD, number nT)
  return setPistonData(self, this, iD, nT, 1)
end

__e2setcost(20)
e2function entity entity:setPistonSign(string iD, number nT)
  return setPistonData(self, this, iD, nT, 1)
end

__e2setcost(20)
e2function entity entity:setPistonWave(number iD, number nT)
  return setPistonData(self, this, iD, nT, 2)
end

__e2setcost(20)
e2function entity entity:setPistonWave(string iD, number nT)
  return setPistonData(self, this, iD, nT, 2)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(number iD, vector vT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, vT, 3, tSpot.Axis)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, vT, 3, tSpot.Axis)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(number iD, vector vT, vector vA)
  return setPistonData(self, this, iD, vT, 3, vA)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT, vector vA)
  return setPistonData(self, this, iD, vT, 3, vA)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(number iD, vector vT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, vT, 4, tSpot.Axis)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, vT, 4, tSpot.Axis)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(number iD, vector vT, vector vA)
  return setPistonData(self, this, iD, vT, 4, vA)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT, vector vA)
  return setPistonData(self, this, iD, vT, 4, vA)
end

__e2setcost(20)
e2function entity entity:setPistonRamp(number iD, number nT)
  return setPistonData(self, this, iD, nT, 5)
end

__e2setcost(20)
e2function entity entity:setPistonRamp(string iD, number nT)
  return setPistonData(self, this, iD, nT, 5)
end

__e2setcost(20)
e2function entity entity:setPistonTroc(number iD, number nT)
  return setPistonData(self, this, iD, nT, 6)
end

__e2setcost(20)
e2function entity entity:setPistonTroc(string iD, number nT)
  return setPistonData(self, this, iD, nT, 6)
end

--[[ **************************** CALCULATE **************************** ]]

__e2setcost(5)
e2function number entity:getPiston(number iD, number nR)
  return getPistonData(this, iD, nR)
end

__e2setcost(5)
e2function number entity:getPiston(string iD, number nR)
  return getPistonData(this, iD, nR)
end

__e2setcost(8)
e2function number entity:getPiston(number iD, vector vR)
  return getPistonData(this, iD, vR)
end

__e2setcost(8)
e2function number entity:getPiston(string iD, vector vR)
  return getPistonData(this, iD, vR)
end

--[[ **************************** HIGN AND LOW POINTS **************************** ]]

__e2setcost(5)
e2function number entity:getPistonMax(number iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, nil, 2)
end

__e2setcost(5)
e2function number entity:getPistonMax(string iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, nil, 2)
end

__e2setcost(5)
e2function number entity:getPistonMin(number iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, nil, 3)
end

__e2setcost(5)
e2function number entity:getPistonMin(string iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, nil, 3)
end

__e2setcost(5)
e2function vector entity:getPistonMaxX(number iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, nil, 2))
end

__e2setcost(5)
e2function vector entity:getPistonMaxX(string iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, nil, 2))
end

__e2setcost(5)
e2function vector entity:getPistonMinX(number iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, nil, 3))
end

__e2setcost(5)
e2function vector entity:getPistonMinX(string iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, nil, 3))
end

--[[ **************************** READ CROSS PRODUCT AXIS **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonAxis(number iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, nil, 5))
end

__e2setcost(5)
e2function vector entity:getPistonAxis(string iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, nil, 5))
end

--[[ **************************** MODES CHECK FLAGS **************************** ]]

__e2setcost(2)
e2function number entity:isPistonSign(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 1) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSign(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 1) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWave(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 2) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWave(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 2) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWaveX(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 3) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWaveX(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 3) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSignX(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 4) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSignX(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 4) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonRamp(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 5) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonRamp(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 5) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonTroc(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 6) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonTroc(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 6) and 1 or 0)
end

--[[ **************************** DELETE **************************** ]]

__e2setcost(5)
e2function entity entity:remPiston(number iD)
  if(not isValid(this)) then return nil end
  local tP = getData(this); if(not tP) then return nil end
  return setData(this, iD)
end

__e2setcost(5)
e2function entity entity:remPiston(string iD)
  if(not isValid(this)) then return nil end
  local tP = getData(this); if(not tP) then return nil end
  return setData(this, iD)
end

__e2setcost(5)
e2function entity entity:clrPiston()
  if(not isValid(this)) then return nil end
  if(not getData(this)) then return nil end
  return setData(this)
end

--[[ **************************** PISTONS COUNT **************************** ]]

__e2setcost(10)
e2function number entity:cntPiston()
  if(not isValid(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  return #tP
end

__e2setcost(15)
e2function number entity:allPiston()
  if(not isValid(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  local iP = 0; for key, val in pairs(tP) do iP = iP + 1 end
  return iP
end
