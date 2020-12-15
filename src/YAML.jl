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

const _constructor = Union{Nothing, Dict}
const _dicttype = Union{Type,Function}

# add a dicttype-aware version of construct_mapping to the constructors
function _patch_constructors(more_constructors::_constructor, dicttype::_dicttype)
    if more_constructors == nothing
        more_constructors = Dict{String,Function}()
    else
        more_constructors = copy(more_constructors) # do not change the outside world
    end
    if !haskey(more_constructors, "tag:yaml.org,2002:map")
        more_constructors["tag:yaml.org,2002:map"] = custom_mapping(dicttype) # map to the custom type
    elseif dicttype != Dict{Any,Any} # only warn if another type has explicitly been set
        @warn "dicttype=$dicttype has no effect because more_constructors has the key \"tag:yaml.org,2002:map\""
    end
    return more_constructors
end

function load(ts::TokenStream, constructor::Constructor)
    events = EventStream(ts)
    node = compose(events)
    return construct_document(constructor, node)
end

function load(input::IO, constructor::Constructor)
    load(TokenStream(input), constructor)
end
load(input::Union{IO,TokenStream}; dicttype::_dicttype=Dict{Any,Any}) = load(input, SafeConstructor(_patch_constructors(nothing,dicttype)))
load(input::Union{IO,TokenStream}, constructors::Dict, multi_constructors::Dict = Dict(); dicttype::_dicttype=Dict{Any, Any}) = load(input, SafeConstructor(_patch_constructors(constructors,dicttype), multi_constructors))



mutable struct YAMLDocIterator
    input::IO
    ts::TokenStream
    constructor::Constructor
    next_doc

    function YAMLDocIterator(input::IO, constructor::Constructor)
        it = new(input, TokenStream(input), constructor, nothing)
        it.next_doc = eof(it.input) ? nothing : load(it.ts, it.constructor)
        return it
    end
end

YAMLDocIterator(input::IO; dicttype::_dicttype) = YAMLDocIterator(input, SafeConstructor(_patch_constructors(nothing,dicttype)))
YAMLDocIterator(input::IO, constructors::Dict, multi_constructors::Dict = Dict(); dicttype::_dicttype=Dict{Any, Any}) = YAMLDocIterator(input, SafeConstructor(_patch_constructors(constructors,dicttype), multi_constructors))

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

function load_all(input::IO, args...;kwargs...)
    YAMLDocIterator(input, args...;kwargs...)
end

function load(input::AbstractString, args...; kwargs...)
    load(IOBuffer(input), args...; kwargs...)
end

function load_all(input::AbstractString, args...; kwargs...)
    load_all(IOBuffer(input), args...; kwargs...)
end

function load_file(filename::AbstractString, args...; kwargs...)
    open(filename, "r") do input
        load(input, args...; kwargs...)
    end
end

function load_all_file(filename::AbstractString, args...; kwargs...)
    open(filename, "r") do input
        load_all(input, args...; kwargs...)
    end
end

end  # module
