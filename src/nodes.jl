
abstract type Node end

mutable struct ScalarNode <: Node
    tag::String
    value::String
    start_mark::Union{Mark, Nothing}
    end_mark::Union{Mark, Nothing}
    style::Union{Char, Nothing}
end


mutable struct SequenceNode <: Node
    tag::String
    value::Vector
    start_mark::Union{Mark, Nothing}
    end_mark::Union{Mark, Nothing}
    flow_style::Bool
end


mutable struct MappingNode <: Node
    tag::String
    value::Vector
    start_mark::Union{Mark, Nothing}
    end_mark::Union{Mark, Nothing}
    flow_style::Bool
end
