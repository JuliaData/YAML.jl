
abstract Node

type ScalarNode <: Node
    tag::String
    value::String
    start_mark::Union(Mark, Nothing)
    end_mark::Union(Mark, Nothing)
    style::Union(Char, Nothing)
end


type SequenceNode <: Node
    tag::String
    value::Vector
    start_mark::Union(Mark, Nothing)
    end_mark::Union(Mark, Nothing)
    flow_style::Bool
end


type MappingNode <: Node
    tag::String
    value::Vector
    start_mark::Union(Mark, Nothing)
    end_mark::Union(Mark, Nothing)
    flow_style::Bool
end

