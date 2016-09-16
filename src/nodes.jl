
abstract Node

type ScalarNode <: Node
    tag::String
    value::String
    start_mark::(@compat Union{Mark, Void})
    end_mark::(@compat Union{Mark, Void})
    style::(@compat Union{Char, Void})
end


type SequenceNode <: Node
    tag::String
    value::Vector
    start_mark::(@compat Union{Mark, Void})
    end_mark::(@compat Union{Mark, Void})
    flow_style::Bool
end


type MappingNode <: Node
    tag::String
    value::Vector
    start_mark::(@compat Union{Mark, Void})
    end_mark::(@compat Union{Mark, Void})
    flow_style::Bool
end

