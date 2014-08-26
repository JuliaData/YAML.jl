
require("Dates")
require("Codecs")
require("LazySequences")

module YAML
    using LazySequences
    using Dates
    import Codecs
    import Base: isempty, length, show


    include("scanner.jl")
    include("parser.jl")
    include("composer.jl")
    include("constructor.jl")


    function load(input::IO)
        events = parse(input)
        node = compose(events)[1]
        construct_document(Constructor(), node)
    end


    function load_all(input::IO)
        events = parse(input)
        constructor = YAML.Constructor()
        function next_document(events)
            if events === nothing
                return nothing
            end
            node, events = compose(events)
            cons(construct_document(constructor, node),
                 @lazyseq next_document(events))
        end
        next_document(events)
    end

    load(input::String) = load(IOBuffer(input))
    load_all(input::String) = load_all(IOBuffer(input))


    function load_file(filename::String)
        input = open(filename)
        data = load(input)
        close(input)
        data
    end


    function load_all_file(filename::String)
        input = open(filename)
        data = load_all(input)
        close(input)
        data
    end
end

