local tableConcat = table and table.concat
local tableCopy   = table and table.Copy
local mathSqrt    = math and math.sqrt
local mathSin     = math and math.sin
local mathAbs     = math and math.abs
local outError    = error -- The function which generates error and prints it out
local outPrint    = print -- The function that outputs a string into the console
local tF, gnD2R   = {}, (math.pi / 180)
local gsKey       = "wire_e2_piston_timing"
local gwAxis, gwZero, geBase = {0,0,0}, {0,0,0}, nil -- Global axis and base ntity
local gvRoll, gvHigh, gvAxis = Vector(), Vector(), Vector()

E2Lib.RegisterExtension(gsKey, true, "Allows E2 chips to attach pistons to the engine crankshaft props")

local function logError(sM, ...)
  outError("Å2:"..gsKey..":"..tostring(sM)); return ...
end

local function logStatus(sM, ...)
  outPrint("Å2:"..gsKey..":"..tostring(sM)); return ...
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

local function isEntity(oE)
  return (oE and oE:IsValid())
end

local function getData(oE, iD) local tP = oE[gsKey]
  return (tP and (iD and tP[iD] or tP) or nil)
end

local function setData(oE, iD, oV)
  if(isHere(iD)) then oE[gsKey][iD] = oV else oE[gsKey] = oV end
  if(not isHere(oV)) then collectgarbage(); end
  return oE -- Return crankshaft entity
end

local function setVectorWire(vV, tV)
  vV.x = (tonumber(tV[1]) or 0)
  vV.y = (tonumber(tV[2]) or 0)
  vV.z = (tonumber(tV[3]) or 0); return vV
end

local function getCross(tR, tH, tA, oB)
  if(not isEntity(oB)) then return 0 end
  local aB = oB:GetAngles() -- Needed for rotations
  local vR = setVectorWire(gvRoll, tR); vR:Normalize()
  local vH = setVectorWire(gvHigh, tH); vH:Rotate(aB)
  local vA = setVectorWire(gvAxis, tA); vA:Rotate(aB)
  return vH:Cross(vR):Dot(vA)
end

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

--[[
 * oE (entity)         --> Entity of the engine crankshaft. Usually the engine E2 also.
 * iD (number, string) --> Key to store the data by. Either string or a nmber.
 * oT (number, vector) --> Top location of the piston in degrees or
                           local direction vector relative to the base prop.
 * nM (number)         --> Operational mode on initialization. It choses between the
                           defined list of algorithms for obtaining the output function
 * oA (vector)         --> Engine rotational axis local direction vector relative to the
                           base prop used for projections
 * oB (entity)         --> Engine base prop that the shaft is axised to and all other
                           props are also constrained to it. Used for a coordinate reference.
]]
local function setPistonData(oE, iD, oT, nM, oA, oB)
  if(not isEntity(oE)) then return nil end
  local tP, vL, vH, vA = getData(oE); if(not tP) then
    setData(oE, nil, {}); tP = getData(oE) end
  local nM = (tonumber(nM) or 0)
  if(nM) then -- Switch initialization mode
    if(nM == 1 or nM == 2 or nM == 5) then -- Sign [1], sine [2] ramp [5] (number)
      vH, vL = oT, getAngNorm(oT + 180)
    elseif(nM == 3 or nM == 4) then -- Cross product [3], [4] (vector)
      if(not isEntity(oB)) then return logError("Base entity invalid", nil) end
      if(not isWireVecZero(vH)) then return logError("High vector zero", nil) end
      if(not isWireVecZero(vA)) then return logError("Axis vector zero", nil) end
      vH = setWireVecNorm({ oT[1], oT[2], oT[3]})
      vL = setWireVecNorm({-oT[1],-oT[2],-oT[3]})
      vA = setWireVecNorm({ oA[1], oA[2], oA[3]})
    else return logError("Mode ["..tostring(nM).."] not supported", nil) end
    return setData(oE, iD, {tF[nM], vH, vL, nM, vA, oB})
  else return logError("Mode not defined", nil) end 
end

local function getPistonData(oE, iD, vR, iP)
  if(not isEntity(oE)) then return 0 end
  local tP = getData(oE, iD); if(not tP) then return 0 end
  if(iP) then return (tP[iP] or 0) end
  return tP[1](vR, tP[2], tP[3], tP[4], tP[5], tP[6])
end

__e2setcost(1)
e2function entity entity:putPistonBase(entity oB)
  if(oB and oB:IsValid()) then geBase = oB end; return this
end

__e2setcost(1)
e2function entity entity:resPistonBase()
  geBase = nil; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(vector vA)
  setWireVecXYZ(gwAxis, vA[1], vA[2], vA[3]); return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(vector2 vA)
  setWireVecXYZ(gwAxis, vA[1], vA[2], 0); return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(array vA)
  setWireVecXYZ(gwAxis, vA[1], vA[2], vA[3]); return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(number X, number Y, number Z)
  setWireVecXYZ(gwAxis, X, Y, Z); return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(number X, number Y)
  setWireVecXYZ(gwAxis, X, Y, 0); return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(number X)
  setWireVecXYZ(gwAxis, X, 0, 0); return this
end

__e2setcost(1)
e2function entity entity:resPistonAxis()
  setWireVecXYZ(gwAxis, 0, 0, 0); return this
end

__e2setcost(20)
e2function entity entity:setPistonSign(number iD, number nT)
  return setPistonData(this, iD, nT, 1)
end

__e2setcost(20)
e2function entity entity:setPistonSign(string iD, number nT)
  return setPistonData(this, iD, nT, 1)
end

__e2setcost(20)
e2function entity entity:setPistonWave(number iD, number nT)
  return setPistonData(this, iD, nT, 2)
end

__e2setcost(20)
e2function entity entity:setPistonWave(string iD, number nT)
  return setPistonData(this, iD, nT, 2)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(number iD, vector vT)
  return setPistonData(this, iD, vT, 3, gwAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT)
  return setPistonData(this, iD, vT, 3, gwAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(number iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 3, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 3, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(number iD, vector vT)
  return setPistonData(this, iD, vT, 4, gwAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT)
  return setPistonData(this, iD, vT, 4, gwAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(number iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 4, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 4, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonRamp(number iD, number nT)
  return setPistonData(this, iD, nT, 5)
end

__e2setcost(20)
e2function entity entity:setPistonRamp(string iD, number nT)
  return setPistonData(this, iD, nT, 5)
end

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

__e2setcost(5)
e2function vector entity:getPistonAxis(number iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 5))
end

__e2setcost(5)
e2function vector entity:getPistonAxis(string iD)
  return getWireVecCopy(getPistonData(this, iD, nil, 5))
end

__e2setcost(2)
e2function entity entity:getPistonBase(number iD)
  return getPistonData(this, iD, nil, 6)
end

__e2setcost(2)
e2function entity entity:getPistonBase(string iD)
  return getPistonData(this, iD, nil, 6)
end

__e2setcost(5)
e2function entity entity:remPiston(number iD)
  if(not isEntity(this)) then return nil end
  local tP = getData(this); if(not tP) then return nil end
  return setData(this, iD, nil)
end

__e2setcost(5)
e2function entity entity:remPiston(string iD)
  if(not isEntity(this)) then return nil end
  local tP = getData(this); if(not tP) then return nil end
  return setData(this, iD, nil)
end

__e2setcost(5)
e2function entity entity:clrPiston()
  if(not isEntity(this)) then return nil end
  if(not getData(this)) then return nil end
  return setData(this, nil, nil)
end

__e2setcost(10)
e2function number entity:cntPiston()
  if(not isEntity(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  return #tP
end

__e2setcost(15)
e2function number entity:allPiston()
  if(not isEntity(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  local iP = 0; for key, val in pairs(tP) do iP = iP + 1 end
  return iP
end

__e2setcost(2)
e2function vector entity:getPistonTopRoll(vector vR)
  if(not isEntity(this)) then return getWireVecZero() end
  local vV = Vector(); vV:Set(vD); vV:Add(eB:GetPos())
  vV:Set(eB:WorldToLocal(vV)); return getWireVecXYZ(vV.x, vV.y, vV.z)
end
