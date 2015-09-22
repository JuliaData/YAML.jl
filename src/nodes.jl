
abstract Node

type ScalarNode <: Node
    tag::AbstractString
    value::AbstractString
    start_mark::(@compat Union{Mark, Void})
    end_mark::(@compat Union{Mark, Void})
    style::(@compat Union{Char, Void})
end


type SequenceNode <: Node
    tag::AbstractString
    value::Vector
    start_mark::(@compat Union{Mark, Void})
    end_mark::(@compat Union{Mark, Void})
    flow_style::Bool
end


type MappingNode <: Node
    tag::AbstractString
    value::Vector
    start_mark::(@compat Union{Mark, Void})
    end_mark::(@compat Union{Mark, Void})
    flow_style::Bool
end

