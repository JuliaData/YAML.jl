# Constructors for the JSON schema.

construct_undefined_json_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the JSON schema", node.start_mark))

const construct_json_schema_str = construct_failsafe_schema_str

const construct_json_schema_seq = construct_failsafe_schema_seq

const construct_json_schema_map = construct_failsafe_schema_map

function construct_json_schema_null(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    value == "null" ? nothing :
    throw(ConstructorError("not null of the JSON schema", node.start_mark))
end

function construct_json_schema_bool(constructor::Constructor, node::Node)
    value = construct_scalar(constructor, node)
    value == "true"  ? true  :
    value == "false" ? false :
    throw(ConstructorError("not bool of the JSON schema", node.start_mark))
end

function construct_json_schema_int(constructor::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    # decimal
    parse(Int, value, base=10)
end

function construct_json_schema_float(construct::Constructor, node::Node)
    value = string(construct_scalar(constructor, node))
    # fixed or exponential
    parse(Float64, value)
end

const json_schema_constructors = Dict{Union{String, Nothing}, Function}(
    nothing                   => construct_undefined_json_schema,
    "tag:yaml.org,2002:str"   => construct_json_schema_str,
    "tag:yaml.org,2002:seq"   => construct_json_schema_seq,
    "tag:yaml.org,2002:map"   => construct_json_schema_map,
    "tag:yaml.org,2002:null"  => construct_json_schema_null,
    "tag:yaml.org,2002:bool"  => construct_json_schema_bool,
    "tag:yaml.org,2002:int"   => construct_json_schema_int,
    "tag:yaml.org,2002:float" => construct_json_schema_float,
)
