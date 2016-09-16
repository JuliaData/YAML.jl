VERSION >= v"0.4-" && __precompile__()

module YAML

import Base: start, next, done, isempty, length, show
import Codecs
using Compat
import Compat: String

if VERSION < v"0.4-dev"
    using Dates
end

include("scanner.jl")
include("parser.jl")
include("composer.jl")
include("constructor.jl")

typealias _constructor @compat Union{Void,Dict{String,Function}}

function load(ts::TokenStream, more_constructors::_constructor=nothing)
    events = EventStream(ts)
    node = compose(events)
    return construct_document(Constructor(more_constructors), node)
end

function load(input::IO, more_constructors::_constructor=nothing)
    load(TokenStream(input), more_constructors)
end

type YAMLDocIterator
    input::IO
    ts::TokenStream
    next_doc

    function YAMLDocIterator(input::IO)
        it = new(input, TokenStream(input), nothing)
        it.next_doc = eof(it.input) ? nothing : load(it.ts)
        return it
    end
end


start(it::YAMLDocIterator) = nothing

function next(it::YAMLDocIterator, state)
    doc = it.next_doc
    if eof(it.input)
        it.next_doc = nothing
    else
        reset!(it.ts)
        it.next_doc = load(it.ts)
    end
    return doc, nothing
end

done(it::YAMLDocIterator, state) = it.next_doc === nothing

load_all(input::IO) = YAMLDocIterator(input)

function load(input::AbstractString, more_constructors::_constructor=nothing)
    load(IOBuffer(input), more_constructors)
end

load_all(input::AbstractString) = load_all(IOBuffer(input))

function load_file(filename::AbstractString, more_constructors::_constructor=nothing)
    input = open(filename)
    data = load(input, more_constructors)
    close(input)
    data
end


function load_all_file(filename::AbstractString)
    input = open(filename)
    data = load_all(input)
    close(input)
    data
end

end  # module
