VERSION >= v"0.4-" && __precompile__()

module YAML

import Base: start, next, done, isempty, length, show
import Codecs
using Compat
import Compat: String
import Compat: Iterators

if VERSION < v"0.4-dev"
    using Dates
end

include("scanner.jl")
include("parser.jl")
include("composer.jl")
include("constructor.jl")

const _constructor = Union{Void,Dict}

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
    more_constructors::_constructor
    next_doc

    function YAMLDocIterator(input::IO, more_constructors::_constructor=nothing)
        it = new(input, TokenStream(input), more_constructors, nothing)
        it.next_doc = eof(it.input) ? nothing : load(it.ts, it.more_constructors)
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
        it.next_doc = load(it.ts, it.more_constructors)
    end
    return doc, nothing
end

done(it::YAMLDocIterator, state) = it.next_doc === nothing

function load_all(input::IO, more_constructors::_constructor=nothing)
    YAMLDocIterator(input, more_constructors)
end

function load(input::String, more_constructors::_constructor=nothing)
    load(IOBuffer(input), more_constructors)
end

function load_all(input::String, more_constructors::_constructor=nothing)
    load_all(IOBuffer(input), more_constructors)
end

function load_file(filename::String, more_constructors::_constructor=nothing)
    open(filename, "r") do input
        load(input, more_constructors)
    end
end


function load_all_file(filename::String, more_constructors::_constructor=nothing)
    open(filename, "r") do input
        load_all(input, more_constructors)
    end
end

end  # module
