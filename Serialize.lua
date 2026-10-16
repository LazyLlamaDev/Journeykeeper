-- Data codec used by backups and export: deterministic serializer, a strict data-only parser (never executes
-- code), Adler-32 checksum and Base64. Pure Lua 5.1 arithmetic, no bit library, no loadstring.
local _, C = ...
local S = {}; C.Codec = S
local format, byte, char, sub, concat, floor = string.format, string.byte, string.char, string.sub, table.concat, math.floor

local function esc(s)
  return '"' .. s:gsub('[%c"\\\128-\255]', function(c) return format("\\%03d", byte(c)) end) .. '"'
end
local function keyLess(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  if ta == "number" or ta == "string" then return a < b end
  return tostring(a) < tostring(b)
end
local function num(v)
  if v ~= v or v == math.huge or v == -math.huge then return "0" end
  if v == floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then return format("%.0f", v) end
  local s = format("%.14g", v) -- shortest form that round-trips (e.g. 50.3 instead of 50.299999999999997)
  if tonumber(s) == v then return s end
  s = format("%.15g", v); if tonumber(s) == v then return s end
  return format("%.17g", v)
end
local function ser(v, out, depth)
  local t = type(v)
  if t == "string" then out[#out + 1] = esc(v)
  elseif t == "number" then out[#out + 1] = num(v)
  elseif t == "boolean" then out[#out + 1] = v and "true" or "false"
  elseif t == "table" then
    if depth > 40 then out[#out + 1] = "nil"; return end
    local keys = {}
    for k, x in pairs(v) do local tk, tx = type(k), type(x)
      if (tk == "string" or tk == "number" or tk == "boolean") and (tx == "string" or tx == "number" or tx == "boolean" or tx == "table") then keys[#keys + 1] = k end end
    table.sort(keys, keyLess)
    out[#out + 1] = "{"
    for _, k in ipairs(keys) do out[#out + 1] = "["; ser(k, out, depth + 1); out[#out + 1] = "]="; ser(v[k], out, depth + 1); out[#out + 1] = "," end
    out[#out + 1] = "}"
  else out[#out + 1] = "nil" end
end
function S.Serialize(v) local out = {}; ser(v, out, 0); return concat(out) end

-- strict parser for exactly the grammar above; returns value or nil, err
function S.Deserialize(str)
  if type(str) ~= "string" then return nil, "not a string" end
  local pos, n = 1, #str
  local parse
  local function fail(msg) error({ msg = msg .. " at " .. pos }, 0) end
  local function skip() while pos <= n do local c = byte(str, pos); if c == 32 or c == 9 or c == 10 or c == 13 then pos = pos + 1 else break end end end
  local function pstring()
    pos = pos + 1; local buf, start = {}, pos
    while true do
      if pos > n then fail("unterminated string") end
      local c = byte(str, pos)
      if c == 34 then buf[#buf + 1] = sub(str, start, pos - 1); pos = pos + 1; return concat(buf)
      elseif c == 92 then
        buf[#buf + 1] = sub(str, start, pos - 1)
        local d = sub(str, pos + 1, pos + 3)
        if not d:match("^%d%d%d$") then fail("bad escape") end
        local code = tonumber(d); if code > 255 then fail("bad escape") end
        buf[#buf + 1] = char(code); pos = pos + 4; start = pos
      else pos = pos + 1 end
    end
  end
  function parse(depth)
    if depth > 60 then fail("too deep") end
    skip(); local c = sub(str, pos, pos)
    if c == "{" then
      pos = pos + 1; local t = {}
      while true do
        skip()
        if sub(str, pos, pos) == "}" then pos = pos + 1; return t end
        if sub(str, pos, pos) ~= "[" then fail("expected [") end
        pos = pos + 1; local k = parse(depth + 1); skip()
        if sub(str, pos, pos + 1) ~= "]=" then fail("expected ]=") end
        pos = pos + 2; local v = parse(depth + 1); skip()
        if sub(str, pos, pos) ~= "," then fail("expected ,") end
        pos = pos + 1
        if k == nil then fail("nil key") end
        t[k] = v
      end
    elseif c == '"' then return pstring()
    elseif sub(str, pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif sub(str, pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif sub(str, pos, pos + 2) == "nil" then pos = pos + 3; return nil
    else
      local s, e = str:find("^%-?%d+%.?%d*[eE]?[%-+]?%d*", pos)
      if not s then fail("unexpected '" .. c .. "'") end
      local v = tonumber(sub(str, s, e)); if not v then fail("bad number") end
      pos = e + 1; return v
    end
  end
  local ok, res = pcall(function() local v = parse(0); skip(); if pos <= n then fail("trailing data") end; return v end)
  if not ok then return nil, type(res) == "table" and res.msg or tostring(res) end
  return res
end

function S.Checksum(s)
  local a, b = 1, 0
  for i = 1, #s, 4096 do
    local bytes = { byte(s, i, math.min(i + 4095, #s)) }
    for j = 1, #bytes do a = (a + bytes[j]) % 65521; b = (b + a) % 65521 end
  end
  return format("%04x%04x", b, a)
end

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[byte(B64, i)] = i - 1 end
function S.B64Encode(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = byte(s, i, i + 2)
    local v = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = floor(v / 262144) % 64, floor(v / 4096) % 64, floor(v / 64) % 64, v % 64
    out[#out + 1] = sub(B64, c1 + 1, c1 + 1) .. sub(B64, c2 + 1, c2 + 1) .. (b and sub(B64, c3 + 1, c3 + 1) or "=") .. (c and sub(B64, c4 + 1, c4 + 1) or "=")
  end
  return concat(out)
end
function S.B64Decode(s)
  s = s:gsub("[^%w%+/=]", "")
  if #s % 4 ~= 0 then return nil, "bad length" end
  local out = {}
  for i = 1, #s, 4 do
    local q = { byte(s, i, i + 3) }
    local v, pad = 0, 0
    for j = 1, 4 do
      if q[j] == 61 then pad = pad + 1; v = v * 64
      else local d = DEC[q[j]]; if not d then return nil, "bad char" end; v = v * 64 + d end
    end
    local b1, b2, b3 = floor(v / 65536) % 256, floor(v / 256) % 256, v % 256
    out[#out + 1] = char(b1) .. (pad < 2 and char(b2) or "") .. (pad < 1 and char(b3) or "")
  end
  return concat(out)
end

function S.DeepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local t = {}; seen[v] = t
  for k, x in pairs(v) do t[S.DeepCopy(k, seen)] = S.DeepCopy(x, seen) end
  return t
end
