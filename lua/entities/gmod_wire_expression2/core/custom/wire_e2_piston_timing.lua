local tableConcat = table and table.concat
local tableCopy   = table and table.Copy
local mathSqrt    = math and math.sqrt
local mathSin     = math and math.sin
local mathAbs     = math and math.abs
local tF, gnD2R   = {}, (math.pi / 180)
local gsKey       = "wire_e2_piston_timing"
local gtVectors   = {TEMP = Vector()}
local gvAxis, geBase = {0,0,0}, nil
local gsRoll, gsHigh, gsAxis = "ROLL", "HIGH", "AXIS"

local function logStatus(...)
  print(gsKey..": <"..tableConcat({...}, ",")..">")
end

local function logError(...)
  error(gsKey..": <"..tableConcat({...}, ",")..">")
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

local function getVectorCopy(vV)
  return (vV and {vV[1], vV[2], vV[3]} or {0,0,0})
end

local function getArrayNorm(tV) local nN = 0
  for iD = 1, 3 do tV[iD] = (tV[iD] or 0); nN = (nN + tV[iD]^2) end
  nN = mathSqrt(nN); for iD = 1, 3 do tV[iD] = (tV[iD] / nN) end; return tV
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

local function getVector(aK, nX, nY, nZ)
  if(not isHere(aK)) then return gtVectors.TEMP end
  local vC = gtVectors[aK]; if(aK and not gtVectors[aK]) then
    gtVectors[aK] = Vector(); vC = gtVectors[aK] end
  vC.x = (tonumber(nX) or 0)
  vC.y = (tonumber(nY) or 0)
  vC.z = (tonumber(nZ) or 0); return vC
end

local function getCross(tR, tH, tA, oB)
  if(not isEntity(oB)) then return 0 end
  local aB = oB:GetAngles() -- Needed for rotations
  local vR = getVector(gsRoll, tR[1], tR[2], tR[3]); vR:Normalize()
  local vH = getVector(gsHigh, tH[1], tH[2], tH[3]); vH:Rotate(aB)
  local vA = getVector(gsAxis, tA[1], tA[2], tA[3]); vA:Rotate(aB)
  return vH:Cross(vR):Dot(vA)
end

-------- General piston sign routine --------
-- Sign mode [nM=nil] https://en.wikipedia.org/wiki/Square_wave
tF[1] = function(R, H, L) return ((R >= H || R < L) and 1 or -1) end
tF[2] = function(R, H, L) return ((R <= H || R > L) and -1 or 1) end
tF[3] = function(R, H, L) return ((R <= H) and -1 or 1) end

-------- Dedicated mode routines --------
-- Wave  mode [nM=1] https://en.wikipedia.org/wiki/Sine_wave
tF[4] = function(R, H) return mathSin(gnD2R * getAngNorm(R - H)) end
-- Cross product mode [nM=2] https://en.wikipedia.org/wiki/Sine_wave
tF[5] = function(R, H, L, M, A, B) return getCross(R, H, A, B) end
-- Cross product sign mode [nM=3] https://en.wikipedia.org/wiki/Square_wave
tF[6] = function(R, H, L, M, A, B) return getSign(getCross(R, H, A, B)) end
-- Direct ramp force mode [nM=4] https://en.wikipedia.org/wiki/Triangle_wave
tF[7] = function(R, H) local nN = getAngNorm(R - H)
  return (((mathAbs(nN) > 90) and -getAngNorm(nN + 180) or nN) / 90) end

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
  local tP = getData(oE); if(not tP) then
    setData(oE, nil, {}); tP = getData(oE) end
  local vL, vH, vA, iS
  if(nM) then iS = (nM + 3) -- Dedicated modes
    if(nM == 1 or nM == 4) then -- Sine [1] line [4] (number)
      vH, vL = oT, getAngNorm(oT + 180)
    elseif(nM == 2 or nM == 3) then -- Cross product [2],[3] (vector)
      vH = getArrayNorm({ oT[1], oT[2], oT[3]})
      vL = getArrayNorm({-oT[1],-oT[2],-oT[3]})
      vA = getArrayNorm({ oA[1], oA[2], oA[3]})
    end
  else vH = oT; vL = getAngNorm(vH + 180)
    if    (vH > 0) then iS = 1     -- Sign definitions (+)
    elseif(vH < 0) then iS = 2     -- Sign definitions (-)
    else --[[ Zero R ]] iS = 3 end -- Sign definitions (0)
  end; return setData(oE, iD, {tF[iS], vH, vL, (nM or 0), vA, oB})
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
e2function entity entity:putPistonBase()
  geBase = nil; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(vector vA)
  for iD = 1, 3 do gvAxis[iD] = vA[iD] end; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(vector2 vA)
  for iD = 1, 2 do gvAxis[iD] = vA[iD] end; gvAxis[3] = 0; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(array vA)
  for iD = 1, 3 do gvAxis[iD] = (tonumber(vA[iD]) or 0) end; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(number X, number Y, number Z)
  gvAxis[1], gvAxis[2], gvAxis[3] = X, Y, Z; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(number X, number Y)
  gvAxis[1], gvAxis[2], gvAxis[3] = X, Y, 0; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis(number X)
  gvAxis[1], gvAxis[2], gvAxis[3] = X, 0, 0; return this
end

__e2setcost(1)
e2function entity entity:putPistonAxis()
  gvAxis[1], gvAxis[2], gvAxis[3] = 0, 0, 0; return this
end

__e2setcost(20)
e2function entity entity:setPistonSign(number iD, number nT)
  return setPistonData(this, iD, nT)
end

__e2setcost(20)
e2function entity entity:setPistonSign(string iD, number nT)
  return setPistonData(this, iD, nT)
end

__e2setcost(20)
e2function entity entity:setPistonWave(number iD, number nT)
  return setPistonData(this, iD, nT, 1)
end

__e2setcost(20)
e2function entity entity:setPistonWave(string iD, number nT)
  return setPistonData(this, iD, nT, 1)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(number iD, vector vT)
  return setPistonData(this, iD, vT, 3, gvAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT)
  return setPistonData(this, iD, vT, 3, gvAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(number iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 3, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonSignX(string iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 3, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(number iD, vector vT)
  return setPistonData(this, iD, vT, 2, gvAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT)
  return setPistonData(this, iD, vT, 2, gvAxis, geBase)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(number iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 2, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonWaveX(string iD, vector vT, vector vA, entity oB)
  return setPistonData(this, iD, vT, 2, vA, oB)
end

__e2setcost(20)
e2function entity entity:setPistonRamp(number iD, number nT)
  return setPistonData(this, iD, nT, 4)
end

__e2setcost(20)
e2function entity entity:setPistonRamp(string iD, number nT)
  return setPistonData(this, iD, nT, 4)
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
e2function number entity:getMaxPiston(number iD)
  return getPistonData(this, iD, nil, 1)
end

__e2setcost(5)
e2function number entity:getMaxPiston(string iD)
  return getPistonData(this, iD, nil, 1)
end

__e2setcost(5)
e2function number entity:getMinPiston(number iD)
  return getPistonData(this, iD, nil, 2)
end

__e2setcost(5)
e2function number entity:getMinPiston(string iD)
  return getPistonData(this, iD, nil, 2)
end

__e2setcost(5)
e2function vector entity:getMaxPiston(number iD)
  return getVectorCopy(getPistonData(this, iD, nil, 1))
end

__e2setcost(5)
e2function vector entity:getMaxPiston(string iD)
  return getVectorCopy(getPistonData(this, iD, nil, 1))
end

__e2setcost(5)
e2function vector entity:getMinPiston(number iD)
  return getVectorCopy(getPistonData(this, iD, nil, 2))
end

__e2setcost(5)
e2function vector entity:getMinPiston(string iD)
  return getVectorCopy(getPistonData(this, iD, nil, 2))
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
  return getVectorCopy(getPistonData(this, iD, nil, 5))
end

__e2setcost(5)
e2function vector entity:getPistonAxis(string iD)
  return getVectorCopy(getPistonData(this, iD, nil, 5))
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
