
@compat abstract type Node end

type ScalarNode <: Node
    tag::String
    value::String
    start_mark::Union{Mark, Void}
    end_mark::Union{Mark, Void}
    style::Union{Char, Void}
end


type SequenceNode <: Node
    tag::String
    value::Vector
    start_mark::Union{Mark, Void}
    end_mark::Union{Mark, Void}
    flow_style::Bool
end


type MappingNode <: Node
    tag::String
    value::Vector
    start_mark::Union{Mark, Void}
    end_mark::Union{Mark, Void}
    flow_style::Bool
end
