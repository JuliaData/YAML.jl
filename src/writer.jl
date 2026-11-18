#
# Writing Julia collections to YAML files is implemented with multiple dispatch and recursion:
# Depending on the value type, Julia chooses the appropriate _print function, which may add a
# level of recursion.
#

"""
    write_file(path, data, prefix="")

Write some data (e.g. a dictionary or an array) to a YAML file.
"""
function write_file(path::AbstractString, data::Any, prefix::AbstractString="")
    open(path, "w") do io
        write(io, data, prefix)
    end
end

"""
    write([io], data, prefix="")

Write a YAML representation of some data (e.g. a dictionary or an array) to an IO stream,
if provided, or return a string of that representation.
"""
function write(io::IO, data::Any, prefix::AbstractString="")
    print(io, prefix) # print the prefix, e.g. a comment at the beginning of the file
    _print(io, data) # recursively print the data
end

function write(data::Any, prefix::AbstractString="")
    io = IOBuffer()
    write(io, data, prefix)
    str = String(take!(io))
    close(io)
    str
end

"""
    yaml(data)

Return a YAML-formatted string of the `data`.
"""
yaml(data::Any) = write(data)

# recursively print a dictionary
function _print(io::IO, dict::AbstractDict, level::Int=0, ignore_level::Bool=false)
    if isempty(dict)
        println(io, "{}")
    else
        for (i, pair) in enumerate(dict)
            _print(io, pair, level, ignore_level ? i == 1 : false) # ignore indentation of first pair
        end
    end
end

# Julia collections written as YAML sequences
const Sequence = Union{AbstractVector,Tuple,AbstractSet}

_print(io::IO, x::Union{Tuple,AbstractSet}, level::Int=0, ignore_level::Bool=false) =
    _print(io, collect(x), level, ignore_level)

# Julia values written as YAML mappings. YAML has no complex type, so a complex number is
# written as its parts, as JSON.jl does.
const Mapping = Union{AbstractDict,NamedTuple,Complex}

_print(io::IO, x::NamedTuple, level::Int=0, ignore_level::Bool=false) =
    _print(io, pairs(x), level, ignore_level)

_print(io::IO, z::Complex, level::Int=0, ignore_level::Bool=false) =
    _print(io, (re = real(z), im = imag(z)), level, ignore_level)

# a nonempty collection key or value starts on the line after its '?' or key
starts_block(x) = x isa Union{Mapping,Sequence} && !isempty(x)

# recursively print an array
function _print(io::IO, arr::AbstractVector, level::Int=0, ignore_level::Bool=false)
    if isempty(arr)
        println(io, "[]")
    else
        for elem in arr
            if elem isa Sequence && !isempty(elem) # nonempty sequences of sequences must be handled differently
                print(io, _indent("-\n", level))
                _print(io, elem, level + 1)
            else
                print(io, _indent("- ", level))   # print the sequence element identifier '-'
                _print(io, elem, level + 1, true) # print the value directly after
            end
        end
    end
end

# print a single key-value pair
function _print(io::IO, pair::Pair, level::Int=0, ignore_level::Bool=false)
    k = pair[1] isa Union{Symbol,AbstractChar} ? string(pair[1]) : pair[1] # text keys are strings
    if starts_block(k)
        # a collection key is written as an explicit key: '?', the key's lines, then ':'
        println(io, _indent("?", level, ignore_level))
        _print(io, k, level + 1)
        print(io, _indent(":", level))
    else
        key = if k === nothing || k === missing
            "null" # this is what the YAML parser interprets as 'nothing'
        elseif k isa AbstractString
            string_key_needs_quoting(k) ? string("\"", escape_yaml_string(k), "\"") : k
        else
            chomp(sprint(_print, k)) # other keys are written as values are, such as .inf or []
        end
        print(io, _indent(key * ":", level, ignore_level)) # print the key
    end
    if starts_block(pair[2])
        print(io, "\n") # a line break is needed before a recursive structure
    else
        print(io, " ") # a whitespace character is needed before a single value
    end
    _print(io, pair[2], level + 1) # print the value
end

# This needs to cover lots of cases such as
# * The empty string.
# * Contains a comment character.
# * Looks like a sequence or mapping.
# * Looks like a Boolean.
# * Looks like null.
# * Contains whitespace or a non-printable character.
# * Looks like a floating point number, including ".inf" and ".nan".
# * Looks like an integer, including hexadecimal numbers and similar.
# * Looks like a timestamp.
# * Starts with a variety of characters used in YAML syntax.
#
# These rules try to be conservative but may very well still miss some
# corner cases.
function string_key_needs_quoting(s::AbstractString)
    isempty(s) && return true
    occursin('#', s) && return true
    occursin(':', s) && return true
    any(c -> isspace(c) || !isprint(c), s) && return true
    first(s) in "{}[]&*?|-+.<>=!%@:`,\"'" && return true
    isdigit(first(s)) && return true
    s in ("true", "True", "TRUE", "false", "False", "FALSE", "null", "Null", "NULL", "~") && return true
    return false
end

function escape_yaml_string(str::AbstractString)
    # YAML requires four/eight hex digits. Consume escaped backslashes so
    # literal Unicode escape text is left unchanged.
    replace(escape_string(str),
        r"\\(?:\\|u[0-9a-fA-F]{2,4}|U[0-9a-fA-F]{4,8})" =>
        escaped -> escaped[2] == '\\' ? escaped :
            escaped[1:2] * lpad(escaped[3:end], escaped[2] == 'u' ? 4 : 8, '0'))
end

# _print a single string
function _print(io::IO, str::AbstractString, level::Int=0, ignore_level::Bool=false)
    # A reader takes a literal block's indentation from its first line with text. When that line
    # starts with a space, or with a tab (libyaml rejects one there), the header states the
    # indentation instead. Readers disagree on what a top-level header counts from, so a top-level
    # string that needs one is quoted.
    needs_indicator = startswith(lstrip(str, '\n'), (' ', '\t'))
    # Use literal blocks only when non-printable characters are LF or TAB.
    if (occursin('\n', strip(str)) || occursin('"', str)) &&
       all(c -> isprint(c) || c == '\n' || c == '\t', str) && !(level == 0 && needs_indicator)
        # The indicator is 2 because the content sits two spaces deeper than its parent.
        header = needs_indicator ? "|2" : "|"
        if endswith(str, "\n\n")   # multiple trailing newlines: keep
            println(io, header, "+")
            str = str[1:end-1]     # otherwise, we have one too many
        elseif endswith(str, "\n") # one trailing newline: clip
            println(io, header)
        else                       # no trailing newlines: strip
            println(io, header, "-")
        end
        indent = repeat("  ", max(level, 1))
        for line in split(str, "\n")
            println(io, indent, line)
        end
    else
        # quote and escape
        println(io, '"', escape_yaml_string(str), '"')
    end
end

# handle NaNs and Infs
function _print(io::IO, val::AbstractFloat, level::Int=0, ignore_level::Bool=false)
    if isfinite(val)
        # YAML 1.1 readers such as PyYAML and Ruby's Psych read an unsigned exponent as a string
        println(io, replace(string(val), r"e(?=\d)" => "e+"))
    elseif isnan(val)
        println(io, ".NaN") # this is what the YAML parser interprets as NaN
    elseif val == Inf
        println(io, ".inf")
    elseif val == -Inf
        println(io, "-.inf")
    end
end

_print(io::IO, val::Union{Nothing,Missing}, level::Int=0, ignore_level::Bool=false) =
    println(io, "~") # this is what the YAML parser interprets as nothing

# YAML has no rational or irrational type, so these are written as the nearest float, which
# every reader loads as a number
_print(io::IO, val::Union{Rational,AbstractIrrational}, level::Int=0, ignore_level::Bool=false) =
    _print(io, float(val), level, ignore_level)

# Symbols and Chars hold text, so they are written as strings
_print(io::IO, val::Union{Symbol,AbstractChar}, level::Int=0, ignore_level::Bool=false) =
    _print(io, string(val), level, ignore_level)

# _print any other single value
_print(io::IO, val::Any, level::Int=0, ignore_level::Bool=false) =
    println(io, string(val)) # no indentation is required

# add indentation to a string
_indent(str::AbstractString, level::Int, ignore_level::Bool=false) =
    repeat("  ", ignore_level ? 0 : level) * str
