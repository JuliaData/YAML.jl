
abstract Event

immutable StreamStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    encoding::String
end


immutable StreamEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


immutable DocumentStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    explicit::Bool
    version::Union(String, Nothing)
    tags::Union(Dict{String, String}, Nothing)

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
    anchor::Union(String, Nothing)
end


immutable ScalarEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::Union(String, Nothing)
    tag::Union(String, Nothing)
    implicit::Tuple
    value::String
    style::Union(Char, Nothing)
end


immutable SequenceStartEvent <: Event
    start_mark::Mark
    end_mark::Mark
    anchor::Union(String, Nothing)
    tag::Union(String, Nothing)
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
    anchor::Union(String, Nothing)
    tag::Union(String, Nothing)
    implicit::Bool
    flow_style::Bool
end


immutable MappingEndEvent <: Event
    start_mark::Mark
    end_mark::Mark
end


