
# Font handling when pango and fontconfig are not available.

# Define this even if we're not calling pango, since cairo needs it.
const PANGO_SCALE = 1024.0

# Serialized glyph sizes for commont fonts.
const glyphsizes = JSON.parse(
    readall(open(joinpath(Pkg.dir("Compose"), "data", "glyphsize.json"))))


# It's better to overestimate text extents than to underestimes, since the later
# leads to overlaping where the former just results in some extra space. So, we
# scale estimated text extends by this number.
const text_extents_scale_x = 1.0
const text_extents_scale_y = 1.2


# Normalized Levenshtein distance between two strings.
function levenshtein(a::String, b::String)
    a = replace(lowercase(a), r"\s+", "")
    b = replace(lowercase(b), r"\s+", "")
    n = length(a)
    m = length(b)
    D = zeros(Uint, n + 1, m + 1)

    D[:,1] = 0:n
    D[1,:] = 0:m

    for i in 2:n, j in 2:m
        if a[i - 1] == b[j - 1]
            D[i, j] = D[i - 1, j - 1]
        else
            D[i, j] = 1 +  min(D[i - 1, j - 1], D[i, j - 1], D[i - 1, j])
        end
    end

    return D[n,m] / max(n, m)
end


# Find the nearst typeface from the glyph size table.
function match_font(font_family::String)
    ds = [(levenshtein(font_family, k), k) for k in keys(glyphsizes)]
    sort!(ds)
    ds[1][2]
end


# Approximate width of a text in millimeters.
#
# Args:
#   widths: A glyph width table from glyphsizes.
#   text: Any string.
#   size: Font size in points.
#
# Returns:
#   Approximate text width in millimeters.
#
function text_width(widths::Dict, text::String, size::Float64)
    stripped_text = replace(text, r"<[^>]*>", "")
    width = 0
    for c in stripped_text
        width += get(widths, c, widths["w"])
    end
    width
end


function max_text_extents(font_family::String, size::Measure,
                          texts::String...)
    if !isabsolute(size)
        error("text_extents requries font size be in absolute units")
    end
    scale = size / 12pt
    font_family = match_font(font_family)
    height = glyphsizes[font_family]["height"]
    widths = glyphsizes[font_family]["widths"]

    # nudge the height if the text contains <sub> or <sup> tags
    if any([match(r"<su(p|b)>", text) != nothing for text in texts])
        height *= 1.5
    end

    width = maximum([text_width(widths, text, size/pt) for text in texts])
    (text_extents_scale_x * scale * width * mm,
     text_extents_scale_y * scale * height * mm)
end


function text_extents(font_family::String, size::Measure, texts::String...)
    scale = size / 12pt
    font_family = match_font(font_family)
    height = glyphsizes[font_family]["height"]
    widths = glyphsizes[font_family]["widths"]

    extents = Array((Measure, Measure), length(texts))
    for (i, text) in enumerate(texts)
        width = text_width(widths, text, size/pt)*mm
        extents[i] = (width, match(r"<su(p|b)>", text) == nothing ?
                      height * mm : height * 1.5 * mm)
    end

    return extents
end


# Amazingly crude fallback to parse pango markup into svg.
function pango_to_svg(text::String)
    pat = r"<(/?)\s*([^>]*)\s*>"
    input = convert(Array{Uint8}, text)
    output = IOBuffer()
    lastpos = 1
    for mat in eachmatch(pat, text)
        write(output, input[lastpos:mat.offset-1])

        if mat.captures[2] == "sup"
            if mat.captures[1] == "/"
                write(output, "</tspan>")
            else
                # write(output, "<tspan style=\"dominant-baseline:inherit\" baseline-shift=\"super\">")
                write(output, "<tspan style=\"dominant-baseline:inherit\" dy=\"-1ex\">")
            end
        elseif mat.captures[2] == "sub"
            if mat.captures[1] == "/"
                write(output, "</tspan>")
            else
                # write(output, "<tspan style=\"dominant-baseline:inherit\" baseline-shift=\"sub\">")
                write(output, "<tspan style=\"dominant-baseline:inherit\" dy=\"1ex\">")
            end
        elseif mat.captures[2] == "i"
            if mat.captures[1] == "/"
                write(output, "</tspan>")
            else
                write(output, "<tspan style=\"dominant-baseline:inherit\" font-style=\"italic\">")
            end
        elseif mat.captures[2] == "b"
            if mat.captures[1] == "/"
                write(output, "</tspan>")
            else
                write(output, "<tspan style=\"dominant-baseline:inherit\" font-weight=\"bold\">")
            end
        end
        lastpos = mat.offset + length(mat.match)
    end
    write(output, input[lastpos:end])
    bytestring(output)
end

