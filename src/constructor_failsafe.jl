# Constructors for the failsafe schema.

# Parsing utils

struct FailsafeSchemaParseError <: Exception end

# Construct functions

construct_undefined_failsafe_schema(constructor::Constructor, node::Node) =
    throw(ConstructorError("could not determine a constructor for the tag '$(node.tag)' in the failsafe schema", node.start_mark))

construct_failsafe_schema_str(constructor::Constructor, node::Node) =
    string(construct_scalar(constructor, node))

construct_failsafe_schema_seq(constructor::Constructor, node::Node) =
    construct_sequence(constructor, node)

construct_failsafe_schema_map(constructor::Constructor, node::Node) =
    construct_mapping(constructor, node)

const failsafe_schema_constructors = Dict{Union{String, Nothing}, Function}(
    nothing                 => construct_undefined_failsafe_schema,
    "tag:yaml.org,2002:str" => construct_failsafe_schema_str,
    "tag:yaml.org,2002:seq" => construct_failsafe_schema_seq,
    "tag:yaml.org,2002:map" => construct_failsafe_schema_map,
)
