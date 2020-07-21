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
local gsInvType   = "xxxxxx"
local gsKey       = "wire_expression2_pistontiming"
local gtChipInfo  = {} -- Stores the global information for every E2
local gtRoutines  = {} -- Stores global piston routines information
local varEnStatus = CreateConVar(gsKey.."_enst",  0, gnIndependentUsed, "Enables status output messages")
local varDefPrint = CreateConVar(gsKey.."_dprn", "TALK", gnServerControled, "FTrace default status output")
local gsFormLogs  = "E2{%s}{%s}:piston: %s" -- Contains the logs format of the addon
local gsDefPrint  = varDefPrint:GetString() -- Default print location
local gtPrintName = {} -- Contains the print location specification

--[[ **************************** CONFIGURATION **************************** ]]

gtPrintName["NOTIFY" ] = HUD_PRINTNOTIFY
gtPrintName["CONSOLE"] = HUD_PRINTCONSOLE
gtPrintName["TALK"   ] = HUD_PRINTTALK
gtPrintName["CENTER" ] = HUD_PRINTCENTER

--[[ **************************** CALLBACKS **************************** ]]

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
  local nF, nB = getAngNorm(nP), -getAngNorm(nP + 180)
  return (((math.abs(nF) > 90) and nB or nF) / 90)
end

--[[
Calculates vector cross product via axis and highest point
 * tR -> Wiremod vector type of the SHAFT roll marker relative to BASE
 * tH -> Wiremod vector type of the piston highest point relative to BASE
 * tA -> Wiremod vector type of the rotation axis relative to BASE
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
  local tSpot = gtChipInfo[oRefr] -- Index the expression chip spot
  if(not tSpot) then              -- Check expression chip spot presence
    gtChipInfo[oRefr] = {}        -- Allocate table when not available
    tSpot = gtChipInfo[oRefr]     -- Refer the allocated table to store into
    tSpot.Axis = {0,0,0}          -- Rotation axis stored as a local vector relative to BASE
    tSpot.Mark = {0,0,0}          -- Roll zero-mark stored as a local vector relative to SHAFT
    tSpot.Base = nil              -- Entity for overloading and also the engine BASE entity
    tSpot.Tune = 10               -- Global coefficient number for timed piston modes
  end; return tSpot               -- Return expression chip dedicated spot
end

--[[
Converts the mark vector local to the SHAFT entity to
a mark vector local to the BASE entity
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
Reads the piston data from SHAFT entity placeholder
If the iD is not provided returns all SHAFT modifications
 * oE -> The SHAFT entity to check and extract
 * iD -> The piston data to be checked and returned
]]
local function getData(oE, iD) local tP = oE[gsKey]
  return (tP and (iD and tP[iD] or tP) or nil)
end

--[[
Writes the piston data to the SHAFT entity placeholder
If the iD is not provided writes to the SHAFT placeholder
 * oE -> The SHAFT entity to be indexed
 * iD -> The piston key to be used for indexing
 * oV -> The value to be written in the placeholder
]]
local function setData(oE, iD, oV)
  if(iD) then oE[gsKey][iD] = oV else oE[gsKey] = oV end
  return oE -- Return the SHAFT entity
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
function(R, H, L, M, A, N)
  local nN = getAngNorm(R - H)
  return ((math.abs(nN) == 180) and 0 or getSign(nN))
end, "number" }

-- Wave mode [nM=2] https://en.wikipedia.org/wiki/Sine_wave
gtRoutines[2] = {
function(R, H, L, M, A, N)
  return math.sin(gnD2R * getAngNorm(R - H))
end, "number" }

-- Cross product wave mode [nM=3] https://en.wikipedia.org/wiki/Sine_wave
gtRoutines[3] = {
function(R, H, L, M, A, N)
  return getWireCross(R, H, A)
end, "vector" }

-- Cross product sign mode [nM=4] https://en.wikipedia.org/wiki/Square_wave
gtRoutines[4] = {
function(R, H, L, M, A, N)
  return getSign(getWireCross(R, H, A))
end, "vector" }

-- Direct ramp force mode [nM=5] https://en.wikipedia.org/wiki/Triangle_wave
gtRoutines[5] = {
function(R, H, L, M, A, N)
  return getRampNorm(R - H)
end, "number" }

-- Trochoid force mode [nM=6] https://en.wikipedia.org/wiki/Trochoid
gtRoutines[6] = {
function(R, H, L, M, A, N)
  local nP = getAngNorm(R - H)
  local nN = getRampNorm(R - H + 90)
  return getSign(nP) * math.sqrt(1 - nN^2)
end, "number" }

-- https://github.com/dvdvideo1234/E2PistonTiming/blob/master/data/pictures/power_coefficient.PNG
-- Power force mode [nM=7] https://en.wikipedia.org/wiki/Exponentiation
gtRoutines[7] = { -- Change `N` to control power slope r^x
function(R, H, L, M, A, N)
  local nP = getRampNorm(R - H)
  return (getSign(nP) * math.abs(nP)^N)
end, "number" }

-- https://github.com/dvdvideo1234/E2PistonTiming/blob/master/data/pictures/exponential_coefficient.PNG
-- Exponential force mode [nM=8] https://en.wikipedia.org/wiki/Exponentiation
gtRoutines[8] = { -- Change `N` to control exponential slope of e^x
function(R, H, L, M, A, N)
  local nR = getRampNorm(R - H)
  if(N <= 0) then return nR end
  local nA, nK = (N * math.abs(nR)), (1 - math.exp(-N))
  return (1 - math.exp(-nA)) * getSign(nR) / nK
end, "number" }

-- https://github.com/dvdvideo1234/E2PistonTiming/blob/master/data/pictures/logarithmic_coefficient.PNG
-- Logarithmic force mode [nM=9] https://en.wikipedia.org/wiki/Logarithm
gtRoutines[9] = { -- Change `N` to control logarithmic slope
function(R, H, L, M, A, N)
  local nR = getRampNorm(R - H)
  if(N <= 0) then return nR end; nR = nR * N
  local nS, nL = getSign(nR), math.log(N + 1)
  return (math.log(math.abs(nR) + 1) * nS) / nL
end, "number" }

-- https://github.com/dvdvideo1234/E2PistonTiming/blob/master/data/pictures/trapezoidal_coefficient.PNG
-- Trapezoidal force mode [nM=10] https://en.wikipedia.org/wiki/Trapezoid
gtRoutines[10] = { -- Change `N` to control trapezoidal slope
function(R, H, L, M, A, N)
  local nR = getRampNorm(R - H)
  return ((N <= 0) and nR or math.Clamp(nR * N, -1, 1))
end, "number" }


--[[ **************************** WRAPPERS ****************************
 * oS (expression)     --> The instance table of the E2 chip itself
 * oE (entity)         --> Entity of the engine SHAFT. Usually also the engine E2 prop.
 * iD (number, string) --> Key to store the data by. Either string or a number.
 * oT (number, vector) --> Top location of the piston in degrees or
                           local direction vector relative to the BASE prop entity.
 * nM (number)         --> Operational mode on initialization. It chooses between the
                           defined list of algorithms for obtaining the output function
 * oA (vector)         --> Engine rotational axis local direction vector relative to the
                           BASE prop entity used for projections
 * oN (number)         --> General piston tuning coefficient used for routines setup
]]
local function setPistonData(oS, oE, iD, oT, nM, oA, oN)
  if(not isValid(oE)) then return nil end
  local tP = getData(oE); if(not tP) then
    setData(oE, nil, {}); tP = getData(oE) end
  local vL, vH, vA, vN, rT -- Define local variables here
  local nM = (tonumber(nM) or 0) -- Read initialization mode
  local tR = gtRoutines[nM]; if(not tR) then
    return logStatus("Mode ["..nM.."] routine missing", oS) end
  local rF, rT = tR[1], tostring(tR[2] or gsInvType) -- Read routine parameters
  if(not rF) then return logStatus("Mode ["..nM.."] routine function missing", oS) end
  -- Sign [1], sine [2] ramp [5] troc [6] data type (number)
  if(rT == "number") then -- Check number internals
    vH, vL = oT, getAngNorm(oT + 180) -- Normalize the high and low angle
    vN = math.Clamp(tonumber(oN) or 0, 0, 500) -- Store the tuning coefficient
  elseif(rT == "vector") then -- Cross product [3], [4] (vector)
    if(isWireZero(oT)) then return logStatus("Mode ["..nM.."] high vector zero", oS) end
    if(isWireZero(oA)) then return logStatus("Mode ["..nM.."] axis vector zero", oS) end
    vH = setWireDiv(getWireXYZ( oT[1], oT[2], oT[3])) -- Nomalized top vector location
    vL = setWireDiv(getWireXYZ(-oT[1],-oT[2],-oT[3])) -- Nomalized bottom vector location
    vA = setWireDiv(getWireXYZ( oA[1], oA[2], oA[3])) -- Nomalized axis vector
  else return logStatus("Mode ["..nM.."]["..rT.."] not supported", oS) end
  return setData(oE, iD, {rF, vH, vL, nM, vA, vN})
end

local function getPistonData(oE, iD, iP)
  if(not isValid(oE)) then return nil end
  local tP = getData(oE, iD); if(not tP) then return nil end
  if(not iP) then return nil end; return tP[iP]
end

-- Evaluates the piston and always returns a number
local function getPistonEval(oE, iD, vR)
  if(not isValid(oE)) then return 0 end
  local tP = getData(oE, iD); if(not tP) then return 0 end
  return tP[1](vR, tP[2], tP[3], tP[4], tP[5], tP[6])
end

local function enSetupData(oE, iD, sT)
  if(not isValid(oE)) then return false end
  local tP = getData(oE, iD); if(not tP) then return false end
  local nM = tonumber(tP[4] or 0); if(nM <= 0) then return false end
  local tR = gtRoutines[nM]; if(not tR) then return false end
  return (sT == tostring(tR and tR[2] or gsInvType))
end

--[[ **************************** GLOBALS ( TUNING PARAMETER ) **************************** ]]

__e2setcost(1)
e2function void setPistonTune(number nN)
  local tSpot = getExpressionSpot(self)
  tSpot.Tune = math.Clamp(tonumber(nN) or 0, 0, 500)
end

__e2setcost(1)
e2function void resPistonTune()
  local tSpot = getExpressionSpot(self)
  tSpot.Tune = 10 -- Restore the default value
end

--[[ **************************** GLOBALS ( BASE ENTITY ) **************************** ]]

__e2setcost(1)
e2function void setPistonBase(entity oB)
  local tSpot = getExpressionSpot(self)
  tSpot.Base  = (isValid(oB) and oB or nil)
end

__e2setcost(1)
e2function void resPistonBase()
  local tSpot = getExpressionSpot(self)
  tSpot.Base  = nil
end

__e2setcost(1)
e2function entity getPistonBase()
  local tSpot = getExpressionSpot(self)
  return tSpot.Base
end

--[[ **************************** GLOBALS ( BASE AXIS ) **************************** ]]

__e2setcost(5)
e2function vector getPistonAxis()
  local tSpot = getExpressionSpot(self)
  return getWireCopy(tSpot.Axis)
end

__e2setcost(1)
e2function void resPistonAxis()
  local tSpot = getExpressionSpot(self)
  setWireXYZ(tSpot.Axis, 0, 0, 0)
end

__e2setcost(1)
e2function void setPistonAxis(vector vA)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, vA[1], vA[2], vA[3]))
end

__e2setcost(1)
e2function void setPistonAxis(vector2 vA)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, vA[1], vA[2], 0))
end

__e2setcost(1)
e2function void setPistonAxis(array vA)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, vA[1], vA[2], vA[3]))
end

__e2setcost(1)
e2function void setPistonAxis(number nX, number nY, number nZ)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, nX, nY, nZ))
end

__e2setcost(1)
e2function void setPistonAxis(number nX, number nY)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, nX, nY, 0))
end

__e2setcost(1)
e2function void setPistonAxis(number nX)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Axis, nX, 0, 0))
end

--[[ **************************** GLOBALS ( SHAFT MARK ) **************************** ]]

__e2setcost(5)
e2function vector getPistonMark()
  local tSpot = getExpressionSpot(self)
  return getWireCopy(tSpot.Mark)
end

__e2setcost(1)
e2function void resPistonMark()
  local tSpot = getExpressionSpot(self)
  setWireXYZ(tSpot.Mark, 0, 0, 0)
end

__e2setcost(1)
e2function void setPistonMark(vector vM)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, vM[1], vM[2], vM[3]))
end

__e2setcost(1)
e2function void setPistonMark(vector2 vM)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, vM[1], vM[2], 0))
end

__e2setcost(1)
e2function void setPistonMark(array vM)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, vM[1], vM[2], vM[3]))
end

__e2setcost(1)
e2function void setPistonMark(number nX, number nY, number nZ)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, nX, nY, nZ))
end

__e2setcost(1)
e2function void setPistonMark(number nX, number nY)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, nX, nY, 0))
end

__e2setcost(1)
e2function void setPistonMark(number nX)
  local tSpot = getExpressionSpot(self)
  setWireDiv(setWireXYZ(tSpot.Mark, nX, 0, 0))
end

--[[ **************************** LOCALS ( SHAFT MARK ) **************************** ]]

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
e2function vector entity:cnvPistonMark(number nX, number nY, number nZ)
  local tSpot = getExpressionSpot(self)
  return getMarkBase(getWireXYZ(nX, nY, nZ), this, tSpot.Base)
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

__e2setcost(20)
e2function entity entity:setPistonPowr(number iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 7, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonPowr(string iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 7, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonPowr(number iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 7, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonPowr(string iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 7, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonExpo(number iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 8, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonExpo(string iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 8, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonExpo(number iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 8, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonExpo(string iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 8, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonLogn(number iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 9, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonLogn(string iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 9, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonLogn(number iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 9, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonLogn(string iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 9, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonTrpz(number iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 10, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonTrpz(string iD, number nT)
  local tSpot = getExpressionSpot(self)
  return setPistonData(self, this, iD, nT, 10, nil, tSpot.Tune)
end

__e2setcost(20)
e2function entity entity:setPistonTrpz(number iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 10, nil, nN)
end

__e2setcost(20)
e2function entity entity:setPistonTrpz(string iD, number nT, number nN)
  return setPistonData(self, this, iD, nT, 10, nil, nN)
end

--[[ **************************** CALCULATE **************************** ]]

__e2setcost(5)
e2function number entity:getPiston(number iD, number nR)
  return getPistonEval(this, iD, nR)
end

__e2setcost(5)
e2function number entity:getPiston(string iD, number nR)
  return getPistonEval(this, iD, nR)
end

__e2setcost(8)
e2function number entity:getPiston(number iD, vector vR)
  return getPistonEval(this, iD, vR)
end

__e2setcost(8)
e2function number entity:getPiston(string iD, vector vR)
  return getPistonEval(this, iD, vR)
end

--[[ **************************** HIGN AND LOW POINTS **************************** ]]

__e2setcost(5)
e2function number entity:getPistonMax(number iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, 2)
end

__e2setcost(5)
e2function number entity:getPistonMax(string iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, 2)
end

__e2setcost(5)
e2function number entity:getPistonMin(number iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, 3)
end

__e2setcost(5)
e2function number entity:getPistonMin(string iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, 3)
end

__e2setcost(5)
e2function vector entity:getPistonMaxX(number iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, 2))
end

__e2setcost(5)
e2function vector entity:getPistonMaxX(string iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, 2))
end

__e2setcost(5)
e2function vector entity:getPistonMinX(number iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, 3))
end

__e2setcost(5)
e2function vector entity:getPistonMinX(string iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, 3))
end

--[[ **************************** ADDITIONAL PARAMETERS **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonAxis(number iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, 5))
end

__e2setcost(5)
e2function vector entity:getPistonAxis(string iD)
  if(not enSetupData(this, iD, "vector")) then return getWireXYZ() end
  return getWireCopy(getPistonData(this, iD, 5))
end

__e2setcost(5)
e2function number entity:getPistonTune(number iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, 6)
end

__e2setcost(5)
e2function number entity:getPistonTune(string iD)
  if(not enSetupData(this, iD, "number")) then return 0 end
  return getPistonData(this, iD, 6)
end

--[[ **************************** MODES CHECK FLAGS **************************** ]]

__e2setcost(2)
e2function number entity:isPistonSign(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 1) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSign(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 1) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWave(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 2) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWave(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 2) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWaveX(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 3) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWaveX(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 3) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSignX(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 4) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSignX(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 4) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonRamp(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 5) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonRamp(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 5) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonTroc(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 6) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonTroc(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 6) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonPowr(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 7) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonPowr(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 7) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonExpo(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 8) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonExpo(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 8) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonLogn(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 9) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonLogn(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 9) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonTrpz(number iD)
  return (((getPistonData(this, iD, 4) or 0) == 10) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonTrpz(string iD)
  return (((getPistonData(this, iD, 4) or 0) == 10) and 1 or 0)
end

--[[ **************************** DELETE **************************** ]]

__e2setcost(5)
e2function entity entity:remPiston(number iD)
  if(not isValid(this)) then return nil end
  local tP = getData(this) -- Are there any pistons
  if(not tP) then return this end -- No pistins here
  return setData(this, iD) -- Wipe the piston indexed
end

__e2setcost(5)
e2function entity entity:remPiston(string iD)
  if(not isValid(this)) then return nil end
  local tP = getData(this) -- Are there any pistons
  if(not tP) then return this end -- No pistins here
  return setData(this, iD) -- Wipe the piston indexed
end

__e2setcost(5)
e2function entity entity:clrPiston()
  if(not isValid(this)) then return nil end -- Vaid SHAFT
  if(not getData(this)) then return nil end -- Check pistins
  return setData(this) -- Wipe all pistin data in the SHAFT
end

--[[ **************************** PISTONS COUNT **************************** ]]

__e2setcost(10)
e2function number entity:cntPiston()
  if(not isValid(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  return #tP -- Return the sequential pistons count
end

__e2setcost(15)
e2function number entity:allPiston()
  if(not isValid(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  local iP = 0; for key, val in pairs(tP) do iP = iP + 1 end
  return iP -- Return all the pistons count
end
