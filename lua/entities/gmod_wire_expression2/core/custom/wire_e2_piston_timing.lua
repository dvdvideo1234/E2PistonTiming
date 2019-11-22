--[[ **************************** CONFIGURATION **************************** ]]

local tableConcat = table and table.concat
local tableCopy   = table and table.Copy
local mathSqrt    = math and math.sqrt
local mathSin     = math and math.sin
local mathAbs     = math and math.abs
local bitBor      = bit and bit.bor
local tF, gnD2R   = {}, (math.pi / 180)
local gsKey       = "wire_e2_piston_timing"
local tChipInfo   = {} -- Stores the global information for every E2
local gvRoll, gvHigh = Vector(), Vector()
local gvAxis, gwZero = Vector(), {0,0,0}

E2Lib.RegisterExtension(gsKey, true, "Allows E2 chips to attach pistons to the engine crankshaft props")

-- Client and server have independent value
local gnIndependentUsed = bitBor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_PRINTABLEONLY)
-- Server tells the client what value to use
local gnServerControled = bitBor(FCVAR_ARCHIVE, FCVAR_NOTIFY, FCVAR_PRINTABLEONLY, FCVAR_REPLICATED)
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

local gsVarName = "" -- This stores current variable name
local gsCbcHash = "_call" -- This keeps suffix realted to the file

gsVarName = varDefPrint:GetName()
cvars.RemoveChangeCallback(gsVarName, gsVarName..gsCbcHash)
cvars.AddChangeCallback(gsVarName, function(sVar, vOld, vNew)
  local sK = tostring(vNew):upper(); if(gtPrintName[sK]) then gsDefPrint = sK end
end, gsVarName..gsCbcHash)

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

local function isHere(aV)
  return (aV ~= nil)
end

local function getWireVecXYZ(nX, nY, nZ)
  return {tonumber(nX) or 0, tonumber(nY) or 0, tonumber(nZ) or 0}
end

local function getWireVecCopy(tV)
  return (tV and tableCopy(tV) or tableCopy(gwZero))
end

local function getWireVecAbs(tV) local nN = 0
  for iD = 1, 3 do nN = nN + (tV[iD] or 0)^2 end
  return mathSqrt(nN)
end

local function setWireVecNorm(tV)
  local nN = getWireVecAbs(tV)
  for iD = 1, 3 do tV[iD] = (tV[iD] / nN) end; return tV
end

local function isWireVecZero(tV)
  local bX = ((tonumber(tV[1]) or 0) == 0)
  local bY = ((tonumber(tV[2]) or 0) == 0)
  local bZ = ((tonumber(tV[3]) or 0) == 0)
  return (bX and bY and bZ)
end

local function setWireVecXYZ(tV, nX, nY, nZ)
  tV[1] = (tonumber(nX) or 0)
  tV[2] = (tonumber(nY) or 0)
  tV[3] = (tonumber(nZ) or 0); return tV
end

local function setVecWire(vV, tV)
  vV.x = (tonumber(tV[1]) or 0)
  vV.y = (tonumber(tV[2]) or 0)
  vV.z = (tonumber(tV[3]) or 0); return vV
end

local function getCross(tR, tH, tA)
  local vR = setVecWire(gvRoll, tR); vR:Normalize()
  local vH = setVecWire(gvHigh, tH)
  local vA = setVecWire(gvAxis, tA)
  return vH:Cross(vR):Dot(vA)
end

local function getMarkBase(tV, oE, oB)
  if(not isValid(oE)) then return getWireVecZero() end
  if(not isValid(oB)) then return getWireVecZero() end
  local vD = Vector(tV[1], tV[2], tV[3]); vD:Rotate(oE)
  vD:Add(oB:GetPos()); vD:Set(oB:WorldToLocal(vD))
  return getWireVecXYZ(vD[1], vD[2], vD[3])
end

function getSpot(oSelf)
  local oRefr = oSelf.entity
  local tSpot = tChipInfo[oRefr]
  if(not isHere(tSpot)) then -- Check expression chip spot
    tChipInfo[oRefr] = {}    -- Allocate table when not available
    tSpot = tChipInfo[oRefr] -- Refer the allocated table to store into
    tSpot.Axis = {0,0,0}     -- Rotation axis stored as a local vector relative to BASE
    tSpot.Mark = {0,0,0}     -- Roll zero-mark stored as a local vector relative to SHAFT
    tSpot.Base = nil         -- Entity for overloading and also the engine BASE entity
  end; return tSpot          -- Return expression chip dedicated spot
end

local function getData(oE, iD) local tP = oE[gsKey]
  return (tP and (iD and tP[iD] or tP) or nil)
end

local function setData(oE, iD, oV)
  if(isHere(iD)) then oE[gsKey][iD] = oV else oE[gsKey] = oV end
  return oE -- Return crankshaft entity
end

--[[ **************************** PISTON ROUTINES **************************** ]]

-------- General piston sign routine --------
-- Sign mode [nM=1] https://en.wikipedia.org/wiki/Square_wave
tF[1] = function(R, H) local nA = getAngNorm(R - H)
  local nB, aA = ((nA >= 0) and 1 or -1), mathAbs(nA)
  return ((aA == 0 or aA == 180) and 0 or nB)
end
-------- Dedicated mode routines --------
-- Wave  mode [nM=2] https://en.wikipedia.org/wiki/Sine_wave
tF[2] = function(R, H)
  return mathSin(gnD2R * getAngNorm(R - H))
end
-- Cross product wave mode [nM=3] https://en.wikipedia.org/wiki/Sine_wave
tF[3] = function(R, H, L, M, A, B)
  return getCross(R, H, A, B)
end
-- Cross product sign mode [nM=4] https://en.wikipedia.org/wiki/Square_wave
tF[4] = function(R, H, L, M, A, B)
  return getSign(getCross(R, H, A, B))
end
-- Direct ramp force mode [nM=5] https://en.wikipedia.org/wiki/Triangle_wave
tF[5] = function(R, H) local nN = getAngNorm(R - H)
  local nA, nM = -getAngNorm(nN + 180), mathAbs(nN)
  return (((nM > 90) and nA or nN) / 90)
end

--[[ **************************** WRAPPERS **************************** ]]

--[[
 * oS (expression)     --> The instance table of the E2 chip itself
 * oE (entity)         --> Entity of the engine crankshaft. Usually the engine E2 also.
 * iD (number, string) --> Key to store the data by. Either string or a nmber.
 * oT (number, vector) --> Top location of the piston in degrees or
                           local direction vector relative to the base prop.
 * nM (number)         --> Operational mode on initialization. It choses between the
                           defined list of algorithms for obtaining the output function
 * oA (vector)         --> Engine rotational axis local direction vector relative to the
                           base prop used for projections
]]
local function setPistonData(oS, oE, iD, oT, nM, oA)
  if(not isValid(oE)) then return nil end
  local tP, vL, vH, vA = getData(oE); if(not tP) then
    setData(oE, nil, {}); tP = getData(oE) end
  local nM = (tonumber(nM) or 0)
  if(nM) then -- Switch initialization mode
    if(nM == 1 or nM == 2 or nM == 5) then -- Sign [1], sine [2] ramp [5] (number)
      vH, vL = oT, getAngNorm(oT + 180) -- Normalize the high and low angle
    elseif(nM == 3 or nM == 4) then -- Cross product [3], [4] (vector)
      if(not isWireVecZero(vH)) then return logStatus("High vector zero", oS) end
      if(not isWireVecZero(vA)) then return logStatus("Axis vector zero", oS) end
      vH = setWireVecNorm({ oT[1], oT[2], oT[3]})
      vL = setWireVecNorm({-oT[1],-oT[2],-oT[3]})
      vA = setWireVecNorm({ oA[1], oA[2], oA[3]})
    else return logStatus("Mode ["..tostring(nM).."] not supported", oS) end
    return setData(oE, iD, {tF[nM], vH, vL, nM, vA})
  else return logStatus("Mode not defined", oS) end
end

local function getPistonData(oE, iD, vR, iP)
  if(not isValid(oE)) then return 0 end
  local tP = getData(oE, iD); if(not tP) then return 0 end
  if(iP) then return (tP[iP] or 0) end
  return tP[1](vR, tP[2], tP[3], tP[4], tP[5])
end

--[[ **************************** GLOBALS ( BASE ENTITY ) **************************** ]]

__e2setcost(1)
e2function entity entity:setPistonBase(entity oB)
  if(oB and oB:IsValid()) then
    local tSpot = getSpot(self)
    tSpot.Base = oB
  end; return this
end

__e2setcost(1)
e2function entity entity:resPistonBase()
  local tSpot = getSpot(self)
  tSpot.Base  = nil; return this
end

__e2setcost(1)
e2function entity entity:getPistonBase()
  local tSpot = getSpot(self)
  local oB = tSpot.Base -- Read base entity
  if(oB and oB:IsValid()) then return oB end
  return nil -- There is no valid base entity
end

--[[ **************************** GLOBALS ( BASE AXIS ) **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonAxis()
  local tSpot = getSpot(self)
  return tSpot.Axis
end

__e2setcost(1)
e2function entity entity:resPistonAxis()
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, 0, 0, 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(vector vA)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, vA[1], vA[2], vA[3]); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(vector2 vA)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, vA[1], vA[2], 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(array vA)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, vA[1], vA[2], vA[3]); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(number X, number Y, number Z)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, X, Y, Z); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(number X, number Y)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, X, Y, 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonAxis(number X)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Axis, X, 0, 0); return this
end

--[[ **************************** GLOBALS ( SHAFT MARK ) **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonMark()
  local tSpot = getSpot(self)
  return tSpot.Mark
end

__e2setcost(1)
e2function entity entity:resPistonMark()
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, 0, 0, 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(vector vA)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, vA[1], vA[2], vA[3]); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(vector2 vA)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, vA[1], vA[2], 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(array vA)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, vA[1], vA[2], vA[3]); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(number X, number Y, number Z)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, X, Y, Z); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(number X, number Y)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, X, Y, 0); return this
end

__e2setcost(1)
e2function entity entity:setPistonMark(number X)
  local tSpot = getSpot(self)
  setWireVecXYZ(tSpot.Mark, X, 0, 0); return this
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
  local tSpot = getSpot(self)
  return setPistonData(self, this, iD, vT, 3, tSpot.Axis)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT)
  local tSpot = getSpot(self)
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
  local tSpot = getSpot(self)
  return setPistonData(self, this, iD, vT, 4, tSpot.Axis)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT)
  local tSpot = getSpot(self)
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

--[[ **************************** READ PARAMETERS **************************** ]]

__e2setcost(5)
e2function number entity:getPistonMax(number iD)
  return getPistonData(this, iD, nil, 2)
end

__e2setcost(5)
e2function number entity:getPistonMax(string iD)
  return getPistonData(this, iD, nil, 2)
end

__e2setcost(5)
e2function number entity:getPistonMin(number iD)
  return getPistonData(this, iD, nil, 3)
end

__e2setcost(5)
e2function number entity:getPistonMin(string iD)
  return getPistonData(this, iD, nil, 3)
end

__e2setcost(5)
e2function vector entity:getPistonMaxX(number iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 2))
end

__e2setcost(5)
e2function vector entity:getPistonMaxX(string iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 2))
end

__e2setcost(5)
e2function vector entity:getPistonMinX(number iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 3))
end

__e2setcost(5)
e2function vector entity:getPistonMinX(string iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 3))
end

--[[ **************************** FLAG STATES **************************** ]]

__e2setcost(2)
e2function number entity:isPistonSign(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 0) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSign(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 0) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWave(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 1) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWave(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 1) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWaveX(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 2) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonWaveX(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 2) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSignX(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 3) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonSignX(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 3) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonRamp(number iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 4) and 1 or 0)
end

__e2setcost(2)
e2function number entity:isPistonRamp(string iD)
  return (((getPistonData(this, iD, nil, 4) or 0) == 4) and 1 or 0)
end

--[[ **************************** READ GLOBALS **************************** ]]

__e2setcost(5)
e2function vector entity:getPistonAxis(number iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 5))
end

__e2setcost(5)
e2function vector entity:getPistonAxis(string iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 5))
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

--[[ **************************** HELPER **************************** ]]

__e2setcost(5)
e2function vector entity:getMark(vector vM, entity oB)
  return getMarkBase(vM, this, oB)
end

__e2setcost(6)
e2function vector entity:getMark(vector vM)
  local tSpot = getSpot(self)
  return getMarkBase(vM, this, tSpot.Base)
end

__e2setcost(6)
e2function vector entity:getMark(entity oB)
  local tSpot = getSpot(self)
  return getMarkBase(tSpot.Mark, this, oB)
end

__e2setcost(6)
e2function vector entity:getMark()
  local tSpot = getSpot(self)
  return getMarkBase(tSpot.Mark, this, tSpot.Base)
end
