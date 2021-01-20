# YAML

[![CI](https://github.com/JuliaData/YAML.jl/workflows/CI/badge.svg)](https://github.com/JuliaData/YAML.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/JuliaData/YAML.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaData/YAML.jl)

[YAML](http://yaml.org/) is a flexible data serialization format that is
designed to be easily read and written by human beings.

This library parses YAML documents into native Julia types and dumps them back into YAML documents.

## Synopsis

For most purposes there is one important function: `YAML.load`, which takes a
string and parses it the first YAML document it finds.

To parse a file use `YAML.load_file`, and to parse every document in a file
use `YAML.load_all` or `YAML.load_all_file`.

Given a YAML document like the following

```yaml
receipt:     Oz-Ware Purchase Invoice
date:        2012-08-06
customer:
    given:   Dorothy
    family:  Gale

items:
    - part_no:   A4786
      descrip:   Water Bucket (Filled)
      price:     1.47
      quantity:  4

    - part_no:   E1628
      descrip:   High Heeled "Ruby" Slippers
      size:      8
      price:     100.27
      quantity:  1

bill-to:  &id001
    street: |
            123 Tornado Alley
            Suite 16
    city:   East Centerville
    state:  KS

ship-to:  *id001

specialDelivery:  >
    Follow the Yellow Brick
    Road to the Emerald City.
    Pay no attention to the
    man behind the curtain.
```

It can be loaded with

```julia
import YAML
data = YAML.load_file("test.yml")
println(data)
```

Which will show you something like this.

```
{"date"=>Aug 6, 2012 12:00:00 AM PDT,"ship-to"=>{"street"=>"123 Tornado Alley\nSuite 16\n","state"=>"KS","city"=>"East Centerville"},"customer"=>{"given"=>"Dorothy","family"=>"Gale"},"specialDelivery"=>"Follow the Yellow Brick\nRoad to the Emerald City.\nPay no attention to the\nman behind the curtain.\n","items"=>{{"price"=>1.47,"descrip"=>"Water Bucket (Filled)","part_no"=>"A4786","quantity"=>4}  …  {"price"=>100.27,"size"=>8,"descrip"=>"High Heeled \"Ruby\" Slippers","part_no"=>"E1628","quantity"=>1}},"bill-to"=>{"street"=>"123 Tornado Alley\nSuite 16\n","state"=>"KS","city"=>"East Centerville"},"receipt"=>"Oz-Ware Purchase Invoice"}
```

Note that ints and floats are recognized, as well as timestamps which are parsed
into CalendarTime objects. Also, anchors and references work as expected,
without making a copy.

Dictionaries are parsed into instances of `Dict{Any,Any}` by default.
You can, however, specify a custom type in which to parse all dictionaries.

```julia
# using Symbol keys
data = YAML.load_file("test.yml"; dicttype=Dict{Symbol,Any})

# maintaining the order from the YAML file
using OrderedCollections
data = YAML.load_file("test.yml"; dicttype=OrderedDict{String,Any})

# specifying a default value
using DataStructures
data = YAML.load_file("test.yml"; dicttype=()->DefaultDict{String,Any}(Missing))
```


## Writing to YAML

Similar to reading files, you can emit Julia objects to YAML files by calling
`write_file`, or to a string object by calling `write`.

For example, you can reproduce the above file from the variable `data`

```julia
import YAML
YAML.write_file("test-output.yml", data)
```

which gives you (omitting the precise format but maintaining the content)

```yaml
receipt: "Oz-Ware Purchase Invoice"
items:
  - part_no: "A4786"
    price: 1.47
    descrip: "Water Bucket (Filled)"
    quantity: 4
  - part_no: "E1628"
    price: 100.27
    size: 8
    descrip: "High Heeled "Ruby" Slippers"
    quantity: 1
customer:
  given: "Dorothy"
  family: "Gale"
ship-to:
  city: "East Centerville"
  street: |
      123 Tornado Alley
      Suite 16

  state: "KS"
bill-to:
  city: "East Centerville"
  street: |
      123 Tornado Alley
      Suite 16

  state: "KS"
specialDelivery: |
    Follow the Yellow Brick Road to the Emerald City. Pay no attention to the man behind the curtain.

date: 2012-08-06
```

## Not yet implemented

  * When writing YAML files, you cannot use additional constructors like you can when reading.
  * Parsing sexigesimal numbers.
  * Fractions of seconds in timestamps.
  * Specific time-zone offsets in timestamps.
  * Application specific tags.
