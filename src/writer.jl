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

# recursively print an array
function _print(io::IO, arr::AbstractVector, level::Int=0, ignore_level::Bool=false)
    if isempty(arr)
        println(io, "[]")
    else
        for elem in arr
            if elem isa AbstractVector && !isempty(elem) # nonempty vectors of vectors must be handled differently
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
    key = if pair[1] === nothing
        "null" # this is what the YAML parser interprets as 'nothing'
    elseif pair[1] isa AbstractString && string_key_needs_quoting(pair[1])
        string("\"", escape_string(pair[1]), "\"") # special keys that require quoting
    else
        string(pair[1]) # any "normal" case
    end

    print(io, _indent(key * ":", level, ignore_level)) # print the key
    if (pair[2] isa AbstractDict || pair[2] isa AbstractVector) && !isempty(pair[2])
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
    occursin(' ', s) && return true
    first(s) in "{}[]&*?|-+.<>=!%@:`,\"'" && return true
    isdigit(first(s)) && return true
    s in ("true", "True", "TRUE", "false", "False", "FALSE") && return true
    return false
end

# _print a single string
function _print(io::IO, str::AbstractString, level::Int=0, ignore_level::Bool=false)
    if occursin('\n', strip(str)) || occursin('"', str)
        if endswith(str, "\n\n")   # multiple trailing newlines: keep
            println(io, "|+")
            str = str[1:end-1]     # otherwise, we have one too many
        elseif endswith(str, "\n") # one trailing newline: clip
            println(io, "|")
        else                       # no trailing newlines: strip
            println(io, "|-")
        end
        indent = repeat("  ", max(level, 1))
        for line in split(str, "\n")
            println(io, indent, line)
        end
    else
        # quote and escape
        println(io, replace(repr(MIME("text/plain"), str), raw"\$" => raw"$"))
    end
end

# handle NaNs and Infs
function _print(io::IO, val::Float64, level::Int=0, ignore_level::Bool=false)
    if isfinite(val)
        println(io, string(val)) # the usual case
    elseif isnan(val)
        println(io, ".NaN") # this is what the YAML parser interprets as NaN
    elseif val == Inf
        println(io, ".inf")
    elseif val == -Inf
        println(io, "-.inf")
    end
end

_print(io::IO, val::Nothing, level::Int=0, ignore_level::Bool=false) =
    println(io, "~") # this is what the YAML parser interprets as nothing

# _print any other single value
_print(io::IO, val::Any, level::Int=0, ignore_level::Bool=false) =
    println(io, string(val)) # no indentation is required

# add indentation to a string
_indent(str::AbstractString, level::Int, ignore_level::Bool=false) =
    repeat("  ", ignore_level ? 0 : level) * str
