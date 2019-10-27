#
# Writing Julia dictionaries to YAML files is implemented with multiple dispatch and recursion:
# Depending on the value type, Julia chooses the appropriate _print function, which may add a
# level of recursion.
#

"""
    write_file(path, data, prefix="")

Write some data (e.g. a dictionary or an array) to a YAML file.
"""
write_file(path::AbstractString, data::Any, prefix::AbstractString="") =
    open(path, "w") do io
        write(io, data, prefix)
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
    return String(take!(io))
end

# recursively print a dictionary
_print(io::IO, dict::Dict, level::Int=0, ignore_level::Bool=false) =
    for (i, pair) in enumerate(dict)
        _print(io, pair, level, ignore_level ? i == 1 : false) # ignore indentation of first pair
    end

# recursively print an array
_print(io::IO, arr::AbstractVector, level::Int=0, ignore_level::Bool=false) =
    for (i, elem) in enumerate(arr)
        if typeof(elem) <: AbstractVector # vectors of vectors must be handled differently
            print(io, _indent("-\n", level))
            _print(io, elem, level + 1)
        else
            print(io, _indent("- ", level))   # print the sequence element identifier '-'
            _print(io, elem, level + 1, true) # print the value directly after
        end
    end

# print a single key-value pair
function _print(io::IO, pair::Pair, level::Int=0, ignore_level::Bool=false)
    key = if typeof(pair[1]) == Nothing
        "null" # this is what the YAML parser interprets as 'nothing'
    elseif typeof(pair[1]) <: Vector && VERSION < v"0.7.0"
        string(convert(Array{Any}, pair[1]))[4:end] # v0.6 prepends the vector type -> remove it
    else
        string(pair[1]) # any useful case
    end
    print(io, _indent(key * ":", level, ignore_level)) # print the key
    if (typeof(pair[2]) <: Dict || typeof(pair[2]) <: AbstractVector)
        print(io, "\n") # a line break is needed before a recursive structure
    else
        print(io, " ") # a whitespace character is needed before a single value
    end
    _print(io, pair[2], level + 1) # print the value
end

# _print a single string, which may contain multiple lines
_print(io::IO, str::AbstractString, level::Int=0, ignore_level::Bool=false) =
    if occursin("\n", str) # handle multi-line strings
        indentation = repeat("  ", level + 1)
        println(io, "|\n$indentation" * replace(str, "\n"=>"\n"*indentation)) # indent each line
    else
        println(io, "\"" * str * "\"") # be very specific about strings
    end

# handle NaNs and Infs
_print(io::IO, val::Float64, level::Int=0, ignore_level::Bool=false) =
    if isfinite(val)
        println(io, string(val)) # the usual case
    elseif isnan(val)
        println(io, ".NaN") # this is what the YAML parser interprets as NaN
    elseif val == Inf
        println(io, ".inf")
    elseif val == -Inf
        println(io, "-.inf")
    end

_print(io::IO, val::Nothing, level::Int=0, ignore_level::Bool=false) =
    println(io, "~") # this is what the YAML parser interprets as nothing

# _print any other single value
_print(io::IO, val::Any, level::Int=0, ignore_level::Bool=false) =
    println(io, string(val)) # no indentation is required

# add indentation to a string
_indent(str::AbstractString, level::Int, ignore_level::Bool=false) =
    repeat("  ", ignore_level ? 0 : level) * str
