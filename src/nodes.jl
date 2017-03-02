
@compat abstract type Node end

type ScalarNode <: Node
    tag::AbstractString
    value::AbstractString
    start_mark::Union{Mark, Void}
    end_mark::Union{Mark, Void}
    style::Union{Char, Void}
end


type SequenceNode <: Node
    tag::AbstractString
    value::Vector
    start_mark::Union{Mark, Void}
    end_mark::Union{Mark, Void}
    flow_style::Bool
end


type MappingNode <: Node
    tag::AbstractString
    value::Vector
    start_mark::Union{Mark, Void}
    end_mark::Union{Mark, Void}
    flow_style::Bool
end
