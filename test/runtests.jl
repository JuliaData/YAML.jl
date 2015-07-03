#!/usr/bin/env julia

import YAML

tests = [
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
    "issue15"
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


function equivalent(x, y)
    x == y
end


testdir = joinpath(Pkg.dir("YAML"), "test")

for test in tests
    data = YAML.load_file(joinpath(testdir, string(test, ".data")))
    expected = evalfile(joinpath(testdir, string(test, ".expected")))
    if !equivalent(data, expected)
        @printf("%s: FAILED\n", test)
        @printf("Expected:\n%s\nParsed:\n%s\n",
                expected, data)
    else
        @printf("%s: PASSED\n", test)
    end
end


