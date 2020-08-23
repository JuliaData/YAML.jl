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

load(ts::TokenStream, more_constructors::_constructor=nothing; dicttype::_dicttype=Dict{Any, Any}) =
    construct_document(Constructor(_patch_constructors(more_constructors, dicttype)), compose(EventStream(ts)))

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

load(input::IO, more_constructors::_constructor=nothing; kwargs...) =
    load(TokenStream(input), more_constructors; kwargs...)

mutable struct YAMLDocIterator
    input::IO
    ts::TokenStream
    more_constructors::_constructor
    next_doc

    function YAMLDocIterator(input::IO, more_constructors::_constructor=nothing; dicttype::_dicttype=Dict{Any, Any})
        it = new(input, TokenStream(input), _patch_constructors(more_constructors, dicttype), nothing)
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

load_all(input::IO, more_constructors::_constructor=nothing; kwargs...) =
    YAMLDocIterator(input, more_constructors; kwargs...)

load(input::AbstractString, more_constructors::_constructor=nothing; kwargs...) =
    load(IOBuffer(input), more_constructors; kwargs...)

load_all(input::AbstractString, more_constructors::_constructor=nothing; kwargs...) =
    load_all(IOBuffer(input), more_constructors; kwargs...)

load_file(filename::AbstractString, more_constructors::_constructor=nothing; kwargs...) =
    open(filename, "r") do input
        load(input, more_constructors; kwargs...)
    end

load_all_file(filename::AbstractString, more_constructors::_constructor=nothing; kwargs...) =
    open(filename, "r") do input
        load_all(input, more_constructors; kwargs...)
    end

end  # module
