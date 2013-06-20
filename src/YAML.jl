
require("LazySequences")

module YAML
    using LazySequences
    import Base.isempty

    include("scanner.jl")
    include("parser.jl")
end
