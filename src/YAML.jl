__precompile__(true)

module YAML

import Base: isempty, length, show

import Base: iterate

using Base64: base64decode
using Dates
using Printf

include("scanner.jl")
include("parser.jl")
include("composer.jl")
include("constructor.jl")
include("writer.jl") # write Julia dictionaries to YAML files

# const _constructor = Union{Nothing, Dict}

function load(ts::TokenStream, constructor::Constructor = SafeConstructor())
    events = EventStream(ts)
    node = compose(events)
    return construct_document(constructor, node)
end

function load(input::IO, constructor::Constructor = SafeConstructor())
    load(TokenStream(input), constructor)
end

load(input, constructors::Dict, multi_constructors::Dict = Dict()) = load(input, SafeConstructor(constructors, multi_constructors))

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

YAMLDocIterator(input::IO, constructors::Dict, multi_constructors::Dict = Dict()) = YAMLDocIterator(input, SafeConstructor(constructors, multi_constructors))

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

function load_all(input::IO, args...)
    YAMLDocIterator(input, args...)
end

function load(input::AbstractString, constructor::Constructor = SafeConstructor())
    load(IOBuffer(input), constructor)
end

function load_all(input::AbstractString, args...)
    load_all(IOBuffer(input), args...)
end

function load_file(filename::AbstractString, args...)
    open(filename, "r") do input
        load(input, args...)
    end
end


function load_all_file(filename::AbstractString, args...)
    open(filename, "r") do input
        load_all(input, args...)
    end
end

end  # module
