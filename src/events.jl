
abstract type Event end

struct StreamStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    encoding::AbstractString
end


struct StreamEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


struct DocumentStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    explicit::Bool
    version::Union{Tuple, Nothing}
    tags::Union{Dict{AbstractString, AbstractString}, Nothing}

    function DocumentStartEvent(start_mark::Mark,end_mark::Mark,
                                explicit::Bool, version=nothing,
                                tags=nothing)
        new(start_mark, end_mark, explicit, version, tags)
    end
end


struct DocumentEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
    explicit::Bool
end


struct AliasEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::Union{AbstractString, Nothing}
end


struct ScalarEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::Union{AbstractString, Nothing}
    tag::Union{AbstractString, Nothing}
    implicit::Tuple
    value::AbstractString
    style::Union{Char, Nothing}
end


struct SequenceStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::Union{AbstractString, Nothing}
    tag::Union{AbstractString, Nothing}
    implicit::Bool
    flow_style::Bool
end


struct SequenceEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


struct MappingStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::Union{AbstractString, Nothing}
    tag::Union{AbstractString, Nothing}
    implicit::Bool
    flow_style::Bool
end


struct MappingEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


