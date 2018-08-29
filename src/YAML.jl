__precompile__(true)

module YAML

import Base: isempty, length, show

if VERSION < v"1.0.0-rc1.0"
    import Base: start, next, done
else
    import Base: iterate
end

import Codecs
using Compat
using Compat.Dates
using Compat.Printf

if VERSION < v"0.7.0-DEV.2915"
    isnumeric(c::Char) = isnumber(c)
end

if VERSION < v"0.7.0-DEV.3526"
    Base.parse(T::Type{Int}, s::AbstractString; base = 10) = parse(T, s, base)
end

include("scanner.jl")
include("parser.jl")
include("composer.jl")
include("constructor.jl")

const _constructor = Union{Nothing, Dict}

function load(ts::TokenStream, more_constructors::_constructor=nothing)
    events = EventStream(ts)
    node = compose(events)
    return construct_document(Constructor(more_constructors), node)
end

function load(input::IO, more_constructors::_constructor=nothing)
    load(TokenStream(input), more_constructors)
end

mutable struct YAMLDocIterator
    input::IO
    ts::TokenStream
    more_constructors::_constructor
    next_doc

    function YAMLDocIterator(input::IO, more_constructors::_constructor=nothing)
        it = new(input, TokenStream(input), more_constructors, nothing)
        it.next_doc = eof(it.input) ? nothing : load(it.ts, it.more_constructors)
        return it
    end
end

# Old iteration protocol:

start(it::YAMLDocIterator) = nothing

function next(it::YAMLDocIterator, state)
    doc = it.next_doc
    if eof(it.input)
        it.next_doc = nothing
    else
        reset!(it.ts)
        it.next_doc = load(it.ts, it.more_constructors)
    end
    return doc, nothing
end

done(it::YAMLDocIterator, state) = it.next_doc === nothing

# 0.7 iteration protocol:

iterate(it::YAMLDocIterator) = next(it, start(it))
iterate(it::YAMLDocIterator, s) = done(it, s) ? nothing : next(it, s)

function load_all(input::IO, more_constructors::_constructor=nothing)
    YAMLDocIterator(input, more_constructors)
end

function load(input::AbstractString, more_constructors::_constructor=nothing)
    load(IOBuffer(input), more_constructors)
end

function load_all(input::AbstractString, more_constructors::_constructor=nothing)
    load_all(IOBuffer(input), more_constructors)
end

function load_file(filename::AbstractString, more_constructors::_constructor=nothing)
    open(filename, "r") do input
        load(input, more_constructors)
    end
end


function load_all_file(filename::AbstractString, more_constructors::_constructor=nothing)
    open(filename, "r") do input
        load_all(input, more_constructors)
    end
end

end  # module
