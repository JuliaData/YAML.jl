VERSION >= v"0.4-" && __precompile__()

module YAML
    import Base: start, next, done, isempty, length, show
    import Codecs
    using Compat
    
    export @yaml_str, @yaml_mstr

    if VERSION < v"0.4-dev"
        using Dates
    end

    include("scanner.jl")
    include("parser.jl")
    include("composer.jl")
    include("constructor.jl")


    function load(ts::TokenStream)
        events = EventStream(ts)
        node = compose(events)
        return construct_document(Constructor(), node)
    end


    function load(input::IO)
        return load(TokenStream(input))
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


    function start(it::YAMLDocIterator)
        nothing
    end


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

    function done(it::YAMLDocIterator, state)
        return it.next_doc === nothing
    end


    function load_all(input::IO)
        YAMLDocIterator(input)
    end



    load(input::AbstractString) = load(IOBuffer(input))
    load_all(input::AbstractString) = load_all(IOBuffer(input))


    function load_file(filename::AbstractString)
        input = open(filename)
        data = load(input)
        close(input)
        data
    end


    function load_all_file(filename::AbstractString)
        input = open(filename)
        data = load_all(input)
        close(input)
        data
    end

    macro yaml_str(ex)
        load(ex)
    end
    macro yaml_mstr(ex)
        load(ex)
    end

end
