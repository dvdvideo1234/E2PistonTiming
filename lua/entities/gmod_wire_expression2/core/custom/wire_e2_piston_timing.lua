local tableConcat  = table and table.concat
local mathSin      = math and math.sin
local tF, nR       = {}, (math.pi / 180)
local sK           = "wire_e2_piston_timing"

tF[1] = function(R, A, B) return ((R >= A || R < B) and 1 or -1) end
tF[2] = function(R, A, B) return ((R <= A || R > B) and -1 or 1) end
tF[3] = function(R, A, B) return ((R <= A) and -1 or 1) end

local function logStatus(...)
  print(sK..": <"..tableConcat({...}, ",")..">")
end

local function getAngNorm(nA)
  return ((nA + 180) % 360 - 180)
end

local function getWave(nB, nT)
  return mathSin(nR * getAngNorm(nB - nT))
end

local function isEntity(oE)
  return (oE and oE:IsValid())
end

local function getData(oE, iD) local tP = oE[sK]
  return (tP and (iD and tP[iD] or tP) or nil)
end

local function setData(oE, iD, oV)
  if(iD) then oE[sK][iD] = oV else oE[sK] = oV end; return oE
end

local function setPiston(oE, iD, nH, bW)
  if(not isEntity(oE)) then return nil end
  local tP = getData(oE); if(not tP) then
    setData(oE, nil, {}); tP = getData(oE) end
  local nL, iS = getAngNorm(nH + 180), 0
  if(nH > 0) then iS = 1 elseif(nH < 0) then iS = 2 else iS = 3 end
  return setData(oE, iD, {nH, nL, tF[iS], tobool(bW)})
end

local function getPiston(oE, iD, nB, iP)
  if(not isEntity(oE)) then return 0 end
  local tP = getData(oE, iD); if(not tP) then return 0 end
  if(iP) then return (tP[iP] or 0) end
  if(tP[4]) then return getWave(nB, tP[1]) end
  return tP[3](nB, tP[1], tP[2])
end

e2function entity entity:setPistonSign(number iD, number nT)
  return setPiston(this, iD, nT, false)
end

e2function entity entity:setPistonSign(string iD, number nT)
  return setPiston(this, iD, nT, false)
end

e2function entity entity:setPistonWave(number iD, number nT)
  return setPiston(this, iD, nT, true)
end

e2function entity entity:setPistonWave(string iD, number nT)
  return setPiston(this, iD, nT, true)
end

e2function number entity:getPiston(number iD, number nB)
  return getPiston(this, iD, nB)
end

e2function number entity:getPiston(string iD, number nB)
  return getPiston(this, iD, nB)
end

e2function number entity:lowPiston(number iD)
  return getPiston(this, iD, nil, 2)
end

e2function number entity:lowPiston(string iD)
  return getPiston(this, iD, nil, 2)
end

e2function number entity:higPiston(number iD)
  return getPiston(this, iD, nil, 1)
end

e2function number entity:higPiston(string iD)
  return getPiston(this, iD, nil, 1)
end

e2function number entity:wavPiston(number iD)
  return (getPiston(this, iD, nil, 4) and 1 or 0)
end

e2function number entity:wavPiston(string iD)
  return (getPiston(this, iD, nil, 4) and 1 or 0)
end

e2function entity entity:remPiston(number iD)
  if(not isEntity(this)) then return nil end
  local tP = getData(this); if(not tP) then return nil end
  return setData(this, iD, nil)
end

e2function entity entity:remPiston(string iD)
  if(not isEntity(this)) then return nil end
  local tP = getData(this); if(not tP) then return nil end
  return setData(this, iD, nil)
end

e2function entity entity:clrPiston()
  if(not isEntity(this)) then return nil end
  if(not getData(this)) then return nil end
  return setData(this, nil, nil)
end

e2function number entity:cntPiston()
  if(not isEntity(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  return #tP
end

e2function number entity:allPiston()
  if(not isEntity(this)) then return 0 end
  local tP = getData(this); if(not tP) then return 0 end
  local iP = 0; for key, val in pairs(tP) do iP = iP + 1 end
  return iP
end

