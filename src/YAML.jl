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

# const _constructor = Union{Nothing, Dict}

function load(ts::TokenStream, constructor::Constructor = SafeConstructor())
    events = EventStream(ts)
    node = compose(events)
    return construct_document(constructor, node)
end

function load(input::IO, constructor::Constructor = SafeConstructor())
    load(TokenStream(input), constructor)
end

mutable struct YAMLDocIterator
    input::IO
    ts::TokenStream
    constructor::Constructor
    next_doc

    function YAMLDocIterator(input::IO, constructor::Constructor = SafeConstructor())
        it = new(input, TokenStream(input), constructor, nothing)
        it.next_doc = eof(it.input) ? nothing : load(it.ts, it.constructor)
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
        it.next_doc = load(it.ts, it.constructor)
    end
    return doc, nothing
end

done(it::YAMLDocIterator, state) = it.next_doc === nothing

# 0.7 iteration protocol:

iterate(it::YAMLDocIterator) = next(it, start(it))
iterate(it::YAMLDocIterator, s) = done(it, s) ? nothing : next(it, s)

function load_all(input::IO, constructor::Constructor = SafeConstructor())
    YAMLDocIterator(input, constructor)
end

function load(input::AbstractString, constructor::Constructor = SafeConstructor())
    load(IOBuffer(input), constructor)
end

function load_all(input::AbstractString, constructor::Constructor = SafeConstructor())
    load_all(IOBuffer(input), constructor)
end

function load_file(filename::AbstractString, constructor::Constructor = SafeConstructor())
    open(filename, "r") do input
        load(input, constructor)
    end
end


function load_all_file(filename::AbstractString, constructor::Constructor = SafeConstructor())
    open(filename, "r") do input
        load_all(input, constructor)
    end
end

end  # module
