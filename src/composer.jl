
include("nodes.jl")
include("resolver.jl")


immutable ComposerError
    context::Union(String, Nothing)
    context_mark::Union(Mark, Nothing)
    problem::Union(String, Nothing)
    problem_mark::Union(Mark, Nothing)
    note::Union(String, Nothing)

    function ComposerError(context=nothing, context_mark=nothing,
                           problem=nothing, problem_mark=nothing,
                           note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end
end


type Composer
    events
    anchors::Dict{String, Node}
    resolver::Resolver
end


function pop_event(composer::Composer)
    event = first(composer.events)
    composer.events = rest(composer.events)
    event
end


function compose(events)
    composer = Composer(events, Dict{String, Node}(), Resolver())
    @assert typeof(pop_event(composer)) == StreamStartEvent
    node = compose_document(composer)
    if typeof(first(composer.events)) == StreamEndEvent
        pop_event(composer)
    else
        @assert typeof(first(composer.events)) == DocumentStartEvent
    end
    node, composer.events
end


function compose_document(composer::Composer)
    @assert typeof(pop_event(composer)) == DocumentStartEvent
    node = compose_node(composer, nothing, nothing)
    @assert typeof(pop_event(composer)) == DocumentEndEvent
    empty!(composer.anchors)
    node
end


function compose_node(composer::Composer, parent::Union(Node, Nothing),
                      index::Union(Int, Node, Nothing))
    event = first(composer.events)
    if typeof(event) == AliasEvent
        pop_event(composer)
        anchor = event.anchor
        if !haskey(composer.anchors, anchor)
            throw(ComposerError(nothing, nothing, "found undefined alias $(anchor)",
                                event.start_mark))
        end
        return composer.anchors[anchor]
    end

    anchor = event.anchor
    if !is(anchor, nothing)
        if haskey(composer.anchors, anchor)
            throw(ComposerError(
                "found duplicate anchor $(anchor); first occurance",
                composer.anchors[anchor].start_mark, "second occurence",
                event.start_mark))
        end
    end

    node = nothing
    if typeof(event) == ScalarEvent
        node = compose_scalar_node(composer, anchor)
    elseif typeof(event) == SequenceStartEvent
        node = compose_sequence_node(composer, anchor)
    elseif typeof(event) == MappingStartEvent
        node = compose_mapping_node(composer, anchor)
    end

    node
end


function compose_scalar_node(composer::Composer, anchor::Union(String, Nothing))
    event = pop_event(composer)
    tag = event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, ScalarNode,
                      event.value, event.implicit)
    end

    node = ScalarNode(tag, event.value, event.start_mark, event.end_mark,
                      event.style)
    if !is(anchor, nothing)
        composer.anchors[anchor] = node
    end

    node
end


function compose_sequence_node(composer::Composer, anchor::Union(String, Nothing))
    start_event = pop_event(composer)
    tag = start_event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, SequenceNode,
                      nothing, start_event.implicit)
    end

    node = SequenceNode(tag, [], start_event.start_mark, nothing,
                        start_event.flow_style)
    if !is(anchor, nothing)
        composer.anchors[anchor] = node
    end

    index = 1
    while typeof(first(composer.events)) != SequenceEndEvent
        push!(node.value, compose_node(composer, node, index))
        index += 1
    end

    end_event = pop_event(composer)
    node.end_mark = end_event.end_mark

    node
end


function compose_mapping_node(composer::Composer, anchor::Union(String, Nothing))
    start_event = pop_event(composer)
    tag = start_event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, MappingNode,
                      nothing, start_event.implicit)
    end

    node = MappingNode(tag, [], start_event.start_mark, nothing,
                       start_event.flow_style)
    if !is(anchor, nothing)
        composer.anchors[anchor] = node
    end

    while typeof(first(composer.events)) != MappingEndEvent
        item_key = compose_node(composer, node, nothing)
        item_value = compose_node(composer, node, item_key)
        push!(node.value, (item_key, item_value))
    end

    end_event = pop_event(composer)
    node.end_mark = end_event.end_mark

    node
end

