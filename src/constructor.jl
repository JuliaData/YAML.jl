

immutable ConstructorError
    context::(@compat Union{AbstractString, Void})
    context_mark::(@compat Union{Mark, Void})
    problem::(@compat Union{AbstractString, Void})
    problem_mark::(@compat Union{Mark, Void})
    note::(@compat Union{AbstractString, Void})

    function ConstructorError(context=nothing, context_mark=nothing,
                              problem=nothing, problem_mark=nothing,
                              note=nothing)
        new(context, context_mark, problem, problem_mark, note)
    end

end

function show(io::IO, error::ConstructorError)
    if error.context != nothing
        print(io, error.context, " at ", error.context_mark, ": ")
    end
    print(io, error.problem, " at ", error.problem_mark)
end


type Constructor
    constructed_objects::Dict{Node, Any}
    recursive_objects::Set{Node}
    deep_construct::Bool
    yaml_constructors::Dict{(@compat Union{AbstractString, Void}), Function}

    function Constructor()
        new(Dict{Node, Any}(), Set{Node}(), false,
            copy(default_yaml_constructors))
    end
end


function construct_document(constructor::Constructor, node::Node)
    data = construct_object(constructor, node)
    empty!(constructor.constructed_objects)
    empty!(constructor.recursive_objects)
    constructor.deep_construct = false
    data
end


function construct_object(constructor::Constructor, node::Node; deep=false)
    if haskey(constructor.constructed_objects, node)
        return constructor.constructed_objects[node]
    end

    if deep
        old_deep = constructor.deep_construct
        constructor.deep_construct = true
    end

    if in(node, constructor.recursive_objects)
        throw(ConstructorError(nothing, nothing,
                               "found unconstructable recursive node",
                               node.start_mark))
    end

    push!(constructor.recursive_objects, node)
    node_constructor = nothing
    tag_suffix = nothing
    if haskey(constructor.yaml_constructors, node.tag)
        node_constructor = constructor.yaml_constructors[node.tag]
    else
        # TODO: Multi-constructors. Constructors that operate on prefixes.

        if haskey(constructor.yaml_constructors, nothing)
            node_constructor = constructor.yaml_constructors[nothing]
        elseif typeof(node) == ScalarNode
            node_constructor = construct_scalar
        elseif typeof(node) == SequenceNode
            node_constructor = construct_sequence
        elseif typeof(node) == MappingNode
            node_constructor = construct_mapping
        end
    end

    if tag_suffix === nothing
        data = node_constructor(constructor, node)
    else
        data = node_constructor(constructor, tag_suffix, node)
    end

    # TODO: Handle generators/iterators

    constructor.constructed_objects[node] = data
    delete!(constructor.recursive_objects, node)
    if deep
        constructor.deep_construct = old_deep
    end

    data
end


function construct_scalar(constructor::Constructor, node::Node)
    if typeof(node) != ScalarNode
        throw(ConstructorError(nothing, nothing,
                               "expected a scalar node, but found $(typeof(node))",
                               node.start_mark))
    end
    node.value
end


function construct_sequence(constructor::Constructor, node::Node; deep=false)
    if typeof(node) != SequenceNode
        throw(ConstructorError(nothing, nothing,
                               "expected a sequence node, but found $(typeof(node))",
                               node.start_mark))
    end

    [construct_object(constructor, child, deep=deep) for child in node.value]
end


function flatten_mapping(node::MappingNode)
    merge = []
    index = 1
    while index <= length(node.value)
        key_node, value_node = node.value[index]
        if key_node.tag == "tag:yaml.org,2002:merge"
            # TODO: stuff
        elseif key_node.tag == "tag:yaml.org,2002:value"
            key_node.tag = "tag:yaml.org,2002:str"
            index += 1
        else
            index += 1
        end
    end

    if !isempty(merge)
        node.value = vcat(merge, node.value)
    end
end


function construct_mapping(constructor::Constructor, node::Node; deep=false)
    if typeof(node) != MappingNode
        throw(ConstructorError(nothing, nothing,
                               "expected a mapping node, but found $(typeof(node))",
                               node.start_mark))
    end

    flatten_mapping(node)
    mapping = Dict()
    for (key_node, value_node) in node.value
        key = construct_object(constructor, key_node, deep=deep)
        value = construct_object(constructor, value_node, deep=deep)
        mapping[key] = value
    end
    mapping
end


function construct_yaml_null(constructor::Constructor, node::Node)
    construct_scalar(constructor, node)
    nothing
end


const bool_values = @compat Dict(
    "yes"   => true,
    "no"    => false,
    "true"  => true,
    "false" => false,
    "on"    => true,
    "off"   => false )


function construct_yaml_bool(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    bool_values[lowercase(value)]
end


function construct_yaml_int(constructor::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    value = lowercase(replace(value, "_", ""))

    if in(':', value)
        # TODO
        #throw(ConstructorError(nothing, nothing,
            #"sexagesimal integers not yet implemented", node.start_mark))
        warn("sexagesimal integers not yet implemented. Returning AbstractString.")
        return value
    end

    if length(value) > 2 && value[1] == '0' && (value[2] == 'x' || value[2] == 'X')
        return parse(Int, value[3:end], 16)
    elseif length(value) > 1 && value[1] == '0'
        return parse(Int, value, 8)
    else
        return parse(Int, value, 10)
    end
end


function construct_yaml_float(constructor::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    value = lowercase(replace(value, "_", ""))

    if in(':', value)
        # TODO
        # throw(ConstructorError(nothing, nothing,
        #     "sexagesimal floats not yet implemented", node.start_mark))
        warn("sexagesimal floats not yet implemented. Returning AbstractString.")
        return value
    end

    if value == ".nan"
        return NaN
    end

    m = match(r"^([+\-]?)\.inf$", value)
    if !is(m, nothing)
        if m.captures[1] == "-"
            return -Inf
        else
            return Inf
        end
    end

    return parse(Float64, value)
end


const timestamp_pat =
    r"^(\d{4})-    (?# year)
       (\d\d?)-    (?# month)
       (\d\d?)     (?# day)
      (?:
        (?:[Tt]|[ \t]+)
        (\d\d?):      (?# hour)
        (\d\d):       (?# minute)
        (\d\d)        (?# second)
        (?:\.(\d*))?  (?# fraction)
        (?:
          [ \t]*(Z|(?:[+\-])(\d\d?)
            (?:
                :(\d\d)
            )?)
        )?
      )?$"x


function construct_yaml_timestamp(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    mat = match(timestamp_pat, value)
    if mat === nothing
        throw(ConstructorError(nothing, nothing,
            "could not make sense of timestamp format", node.start_mark))
    end

    yr = parse(Int, mat.captures[1])
    mn = parse(Int, mat.captures[2])
    dy = parse(Int, mat.captures[3])

    if mat.captures[4] === nothing
        return Date(yr, mn, dy)
    end

    h = parse(Int, mat.captures[4])
    m = parse(Int, mat.captures[5])
    s = parse(Int, mat.captures[6])

    if mat.captures[7] === nothing
        return DateTime(yr, mn, dy, h, m, s)
    end

    ms = 0
    if !is(mat.captures[7], nothing)
        ms = mat.captures[7]
        if length(ms) > 3
            ms = ms[1:3]
        end
        ms = parse(Int, string(ms, repeat("0", 3 - length(ms))))
    end

    delta_hr = 0
    delta_mn = 0

    if !is(mat.captures[9], nothing)
        delta_hr = parse(Int, mat.captures[9])
    end

    if !is(mat.captures[10], nothing)
        delta_mn = parse(Int, mat.captures[10])
    end

    # TODO: Also, I'm not sure if there is a way to numerically set the timezone
    # in Calendar.

    return DateTime(yr, mn, dy, h, m, s, ms)
end


function construct_yaml_omap(constructor::Constructor, node::Node)
    throw(ConstructorError(nothing, nothing,
        "omap type not yet implemented", node.start_mark))
end


function construct_yaml_pairs(constructor::Constructor, node::Node)
    throw(ConstructorError(nothing, nothing,
        "pairs type not yet implemented", node.start_mark))
end


function construct_yaml_set(constructor::Constructor, node::Node)
    throw(ConstructorError(nothing, nothing,
        "set type not yet implemented", node.start_mark))
end


function construct_yaml_str(constructor::Constructor, node::Node)
    string(construct_scalar(constructor, node))
end


function construct_yaml_seq(constructor::Constructor, node::Node)
    construct_sequence(constructor, node)
end


function construct_yaml_map(constructor::Constructor, node::Node)
    construct_mapping(constructor, node)
end


function construct_yaml_object(constructor::Constructor, node::Node)
    throw(ConstructorError(nothing, nothing,
        "object type not yet implemented", node.start_mark))
end


function construct_undefined(constructor::Constructor, node::Node)
    throw(ConstructorError(nothing, nothing,
        "could not determine a constructor for the tag '$(node.tag)'",
        node.start_mark))
end


function construct_yaml_binary(constructor::Constructor, node::Node)
    value = replace(string(construct_scalar(constructor, node)), "\n", "")
    Codecs.decode(Codecs.Base64, value)
end


const default_yaml_constructors = @compat Dict{(@compat Union{AbstractString, Void}), Function}(
        "tag:yaml.org,2002:null"      => construct_yaml_null,
        "tag:yaml.org,2002:bool"      => construct_yaml_bool,
        "tag:yaml.org,2002:int"       => construct_yaml_int,
        "tag:yaml.org,2002:float"     => construct_yaml_float,
        "tag:yaml.org,2002:binary"    => construct_yaml_binary,
        "tag:yaml.org,2002:timestamp" => construct_yaml_timestamp,
        "tag:yaml.org,2002:omap"      => construct_yaml_omap,
        "tag:yaml.org,2002:pairs"     => construct_yaml_pairs,
        "tag:yaml.org,2002:set"       => construct_yaml_set,
        "tag:yaml.org,2002:str"       => construct_yaml_str,
        "tag:yaml.org,2002:seq"       => construct_yaml_seq,
        "tag:yaml.org,2002:map"       => construct_yaml_map,
        nothing                       => construct_undefined
    )


