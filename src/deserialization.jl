# Deserialize a YAML string to a given type.
#
# Example:
# ```
# using Base.Test
#
# type Foo
#    bar::UTF8String
# end
#
# @test deserialize(Foo, """{"bar": "baz"}""") == Foo("baz")
# ```
#
# Nullable fields are considered optional, but all other fields are mandatory.
#
deserialize{T}(::Type{T}, yaml::AbstractString) = deserialize(T, YAML.load(yaml))
deserialize{T}(::Type{T}, yaml::Dict) =
    T([deserialize_field(T, f, yaml) for f in fieldnames(T)]...)
function deserialize{T}(::Type{Array{T,1}}, a::Array{Any,1})
    result = Array{T, 1}()
    for e in a
        element_value = deserialize(T, e)
        push!(result, element_value)
    end
    result
end
deserialize{T<:Integer}(::Type{T}, i::Integer) = T(i)
deserialize{T<:Integer}(::Type{T}, i::AbstractString) = parse(T, i)
deserialize{T<:AbstractFloat}(::Type{T}, i::AbstractFloat) = T(i)
deserialize{T<:AbstractFloat}(::Type{T}, i::AbstractString) = parse(T, i)
deserialize{T<:AbstractString}(::Type{T}, i::AbstractString) = T(i)
deserialize{T}(::Type{Nullable{T}}, yaml::AbstractString) = deserialize(T, yaml)
deserialize{T}(::Type{Nullable{T}}, yaml::Dict) = deserialize(T, yaml)
deserialize{T}(::Type{Nullable{T}}, ::Void) = Nullable{T}()
deserialize{T}(::Type{Nullable{T}}, x) = deserialize(T, x)

# Deserialize a given field (name or symbol) from a Dict, into a given type.
deserialize_field{Tf}(::Type{Tf}, field::AbstractString, yaml::Dict) = deserialize(Tf, yaml[field])
deserialize_field{Tf<:Nullable}(::Type{Tf}, field::AbstractString, yaml::Dict) =
    haskey(yaml, field) ? deserialize(Tf, yaml[field]) : Tf()
deserialize_field{Tf}(ta::Type{Array{Tf}}, field::AbstractString, yaml::Dict) =
    deserialize(ta, yaml[field])

deserialize_field{T}(::Type{T}, field::Symbol, yaml::Dict) =
    deserialize_field(fieldtype(T,field), string(field), yaml)