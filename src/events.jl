
abstract Event

immutable StreamStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    encoding::AbstractString
end


immutable StreamEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


immutable DocumentStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    explicit::Bool
    version::(@compat Union{Tuple, Void})
    tags::(@compat Union{Dict{AbstractString, AbstractString}, Void})

    function DocumentStartEvent(start_mark::Mark,end_mark::Mark,
                                explicit::Bool, version=nothing,
                                tags=nothing)
        new(start_mark, end_mark, explicit, version, tags)
    end
end


immutable DocumentEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
    explicit::Bool
end


immutable AliasEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::(@compat Union{AbstractString, Void})
end


immutable ScalarEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::(@compat Union{AbstractString, Void})
    tag::(@compat Union{AbstractString, Void})
    implicit::Tuple
    value::AbstractString
    style::(@compat Union{Char, Void})
end


immutable SequenceStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::(@compat Union{AbstractString, Void})
    tag::(@compat Union{AbstractString, Void})
    implicit::Bool
    flow_style::Bool
end


immutable SequenceEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


immutable MappingStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::(@compat Union{AbstractString, Void})
    tag::(@compat Union{AbstractString, Void})
    implicit::Bool
    flow_style::Bool
end


immutable MappingEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


