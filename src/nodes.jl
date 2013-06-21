
abstract Node

type ScalarNode <: Node
    tag::String
    value::String
    start_mark::Mark
    end_mark::Mark
    style::Union(Char, Nothing)
end


type SequenceNode <: Node
    tag::String
    value::Vector
    start_mark::Mark
    end_mark::Mark
    flow_style::Bool
end


type MappingNode <: Node
    tag::String
    value::Vector
    start_mark::Mark
    end_mark::Mark
    flow_style::Bool
end

