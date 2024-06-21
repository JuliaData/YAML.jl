"""
    YAMLVersion

A type used for controlling the YAML version.

Planned to be supported versions are:

- [`YAMLV1_1`](@ref): YAML version 1.1
- [`YAMLV1_2`](@ref): YAML version 1.2
"""
abstract type YAMLVersion end

"""
    YAMLV1_1

A singleton type for YAML version 1.1.
"""
struct YAMLV1_1 <: YAMLVersion end

"""
    YAMLV1_2

A singleton type for YAML version 1.2.
"""
struct YAMLV1_2 <: YAMLVersion end
