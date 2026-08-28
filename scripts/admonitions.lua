-- Pandoc fenced div の info / warning / error を Typst テーマの
-- admonition 関数へ変換する。ボックス内の Markdown は AST のまま
-- 返すため、強調・リスト・コードなども通常どおり使える。

local supported = {
  info = true,
  warning = true,
  error = true,
}

function Div(div)
  local kind = nil
  for _, class in ipairs(div.classes) do
    if supported[class] then
      kind = class
      break
    end
  end

  if kind == nil then
    return nil
  end

  local blocks = pandoc.List({
    pandoc.RawBlock("typst", '#admonition(kind: "' .. kind .. '")['),
  })
  blocks:extend(div.content)
  blocks:insert(pandoc.RawBlock("typst", "]"))
  return blocks
end
