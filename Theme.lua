-- v0.7.1: visual themes. "parchment" (default) = new aged-parchment pages, cards and toasts with a compass wax seal;
-- "classic" = the look up to 0.7.0. Purely cosmetic: one saved setting (C.set.theme), additive default, no data touched.
-- Switching is live: every themed texture registers here and is re-skinned on C.Theme.Set.
local _, C = ...
local T = { VALUES = { parchment = true, classic = true }, ORDER = { "parchment", "classic" } }
C.Theme = T
-- base media name -> parchment-theme variant
T.MAP = { book = "book_p", toast_parchment = "toast_parchment_p", card = "card_p" }
local regs = {}
function T.Get() local v = C.set and C.set.theme; return T.VALUES[v or ""] and v or "parchment" end
function T.IsParchment() return T.Get() == "parchment" end
function T.Tex(name)
  local v = T.IsParchment() and T.MAP[name]
  return C.MEDIA .. (v or name)
end
-- register a texture object to follow the theme; extra(tex, isParchment) may adjust coords/colors
function T.Skin(tex, name, extra)
  if not tex then return end
  regs[#regs + 1] = { tex = tex, name = name, extra = extra }
  tex:SetTexture(T.Tex(name)); if extra then pcall(extra, tex, T.IsParchment()) end
  return tex
end
local hooks = {}
function T.OnChange(fn) hooks[#hooks + 1] = fn end
function T.Apply()
  local p = T.IsParchment()
  for _, r in ipairs(regs) do r.tex:SetTexture(T.Tex(r.name)); if r.extra then pcall(r.extra, r.tex, p) end end
  for _, fn in ipairs(hooks) do pcall(fn, p) end
end
function T.Set(v)
  v = v and v:lower()
  if not T.VALUES[v or ""] then return false end
  C.set.theme = v; T.Apply()
  return true
end
function T.Command(rest)
  rest = (rest or ""):lower():match("^%s*(%S*)")
  if rest == "" then
    local nxt = T.IsParchment() and "classic" or "parchment"; T.Set(nxt); C.Print("layout: " .. nxt .. "  (/jkp layout parchment|classic)")
  elseif T.Set(rest) then C.Print("layout: " .. rest)
  else C.Print("usage: /jkp layout parchment|classic  (current: " .. T.Get() .. ")") end
end
