
[YAML](http://yaml.org/) is a flexible data serialization format that is
designed to be easily read and written by humans beings.

This library parses YAML documents into native Julia types. (Dumping Julia
objects to YAML has not yet been implemented.)

## Synopsis

For most purposes there is one important function: `YAML.load`.

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

data = YAML.load(open("test.yml"))

println(data)
```

Which will show you something like this.

```
{"date"=>Aug 6, 2012 12:00:00 AM PDT,"ship-to"=>{"street"=>"123 Tornado Alley\nSuite 16\n","state"=>"KS","city"=>"East Centerville"},"customer"=>{"given"=>"Dorothy","family"=>"Gale"},"specialDelivery"=>"Follow the Yellow Brick\nRoad to the Emerald City.\nPay no attention to the\nman behind the curtain.\n","items"=>{{"price"=>1.47,"descrip"=>"Water Bucket (Filled)","part_no"=>"A4786","quantity"=>4}  …  {"price"=>100.27,"size"=>8,"descrip"=>"High Heeled \"Ruby\" Slippers","part_no"=>"E1628","quantity"=>1}},"bill-to"=>{"street"=>"123 Tornado Alley\nSuite 16\n","state"=>"KS","city"=>"East Centerville"},"receipt"=>"Oz-Ware Purchase Invoice"}
```

Note that ints and floats are recognized, as well as timestamps which are parsed
into CalendarTime objects. Also, anchors and references work as expected,
without making a copy.


