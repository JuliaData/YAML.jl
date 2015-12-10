
include("nodes.jl")
include("resolver.jl")


immutable ComposerError
    context::(@compat Union{AbstractString, Void})
    context_mark::(@compat Union{Mark, Void})
    problem::(@compat Union{AbstractString, Void})
    problem_mark::(@compat Union{Mark, Void})
    note::(@compat Union{AbstractString, Void})

    function ComposerError(context=nothing, context_mark=nothing,
                           problem=nothing, problem_mark=nothing,
                           note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end
end

function show(io::IO, error::ComposerError)
    if error.context != nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end


type Composer
    input::EventStream
    anchors::Dict{AbstractString, Node}
    resolver::Resolver
end


function compose(events)
    composer = Composer(events, Dict{AbstractString, Node}(), Resolver())
    @assert typeof(forward!(composer.input)) == StreamStartEvent
    node = compose_document(composer)
    if typeof(peek(composer.input)) == StreamEndEvent
        forward!(composer.input)
    else
        @assert typeof(peek(composer.input)) == DocumentStartEvent
    end
    node
end


function compose_document(composer::Composer)
    @assert typeof(forward!(composer.input)) == DocumentStartEvent
    node = compose_node(composer, nothing, nothing)
    @assert typeof(forward!(composer.input)) == DocumentEndEvent
    empty!(composer.anchors)
    node
end


function compose_node(composer::Composer, parent::(@compat Union{Node, Void}),
                      index::(@compat Union{Int, Node, Void}))
    event = peek(composer.input)
    if typeof(event) == AliasEvent
        forward!(composer.input)
        anchor = event.anchor
        if !haskey(composer.anchors, anchor)
            throw(ComposerError(nothing, nothing, "found undefined alias '$(anchor)'",
                                event.start_mark))
        end
        return composer.anchors[anchor]
    end

    anchor = event.anchor
    if !is(anchor, nothing)
        if haskey(composer.anchors, anchor)
            throw(ComposerError(
                "found duplicate anchor '$(anchor)'; first occurance",
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


function compose_scalar_node(composer::Composer, anchor::(@compat Union{AbstractString, Void}))
    event = forward!(composer.input)
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


function compose_sequence_node(composer::Composer, anchor::(@compat Union{AbstractString, Void}))
    start_event = forward!(composer.input)
    tag = start_event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, SequenceNode,
                      nothing, start_event.implicit)
    end

    node = SequenceNode(tag, Any[], start_event.start_mark, nothing,
                        start_event.flow_style)
    if !is(anchor, nothing)
        composer.anchors[anchor] = node
    end

    index = 1
    while typeof(peek(composer.input)) != SequenceEndEvent
        push!(node.value, compose_node(composer, node, index))
        index += 1
    end

    end_event = forward!(composer.input)
    node.end_mark = end_event.end_mark

    node
end


function compose_mapping_node(composer::Composer, anchor::(@compat Union{AbstractString, Void}))
    start_event = forward!(composer.input)
    tag = start_event.tag
    if tag === nothing || tag == "!"
        tag = resolve(composer.resolver, MappingNode,
                      nothing, start_event.implicit)
    end

    node = MappingNode(tag, Any[], start_event.start_mark, nothing,
                       start_event.flow_style)
    if !is(anchor, nothing)
        composer.anchors[anchor] = node
    end

    while typeof(peek(composer.input)) != MappingEndEvent
        item_key = compose_node(composer, node, nothing)
        item_value = compose_node(composer, node, item_key)
        push!(node.value, (item_key, item_value))
    end

    end_event = forward!(composer.input)
    node.end_mark = end_event.end_mark

    node
end

