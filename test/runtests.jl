#!/usr/bin/env julia

module YAMLTests

import YAML
import Base.Filesystem
using Compat.Test

const tests = [
    "spec-02-01",
    "spec-02-02",
    "spec-02-03",
    "spec-02-04",
    "spec-02-05",
    "spec-02-06",
    "spec-02-07",
    "spec-02-08",
    "spec-02-09",
    "spec-02-10",
    "spec-02-11",
    "spec-02-12",
    "spec-02-13",
    "spec-02-14",
    "spec-02-15",
    "spec-02-16",
    "spec-02-17",
    "spec-02-18",
    "spec-02-19",
    "spec-02-20",
    "spec-02-21",
    "spec-02-22",
    "spec-02-23",
    "empty_scalar",
    "no_trailing_newline",
    "windows_newlines",
    "escape_sequences",
    "issue15",
    "issue30",
    "issue36",
    "issue39",
    "cartesian",
    "ar1",
    "ar1_cartesian",
    "merge-01"
]

# ignore some test cases in write_and_load testing
const test_write_ignored = [
    "spec-02-17",
    "escape_sequences",
    "cartesian",
    "ar1",
    "ar1_cartesian"
]


function equivalent(xs::Dict, ys::Dict)
    if Set(collect(keys(xs))) != Set(collect(keys(ys)))
        return false
    end

    for k in keys(xs)
        if !equivalent(xs[k], ys[k])
            return false
        end
    end

    true
end


function equivalent(xs::AbstractArray, ys::AbstractArray)
    if length(xs) != length(ys)
        return false
    end

    for (x, y) in zip(xs, ys)
        if !equivalent(x, y)
            return false
        end
    end

    true
end


function equivalent(x::Float64, y::Float64)
    isnan(x) && isnan(y) ? true : x == y
end


function equivalent(x::AbstractString, y::AbstractString)
    while endswith(x, "\n")
        x = x[1:end-1] # trailing newline characters are ambiguous
    end
    while endswith(y, "\n")
        y = y[1:end-1]
    end
    x == y
end

function equivalent(x, y)
    x == y
end


# test custom tags
function construct_type_map(t::Symbol, constructor::YAML.Constructor,
                            node::YAML.Node)
    mapping = YAML.construct_mapping(constructor, node)
    mapping[:tag] = t
    mapping
end

const more_constructors = let
    pairs = [("!Cartesian", :Cartesian),
             ("!AR1", :AR1)]
    Dict{String,Function}([(t, (c, n) -> construct_type_map(s, c, n))
                           for (t, s) in pairs])
end

# write a file, then load its contents to be tested again
function write_and_load(data::Any)
    path = Filesystem.tempname() * ".yml" # path to a temporary file
    try
        YAML.write_file(path, data)
        return YAML.load_file(path, more_constructors)
    finally
        Filesystem.rm(path, force=true)
    end
end


const testdir = dirname(@__FILE__)
@testset for test in tests
    data = YAML.load_file(
        joinpath(testdir, string(test, ".data")),
        more_constructors
    )
    expected = evalfile(joinpath(testdir, string(test, ".expected")))
    @test equivalent(data, expected)
    if !in(test, test_write_ignored)
        @test equivalent(write_and_load(data), expected)
    else
        println("WARNING: I do not test the writing of $test")
    end
end

end  # module
