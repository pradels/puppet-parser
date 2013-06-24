# Puppet Parser

Parse puppet manifests and generate YAML output of defined nodes and
classes. Provide informations like defined resources, resource overrides,
parameters, includes and variables.

**Note:** This parser started as a fork of 
[puppet-parse](https://github.com/johanek/puppet-parse) project. After changes
to multiple files and need to generate more output information I ended up with
completely rewritten code around existing puppet parser.

## Features

* Parses:
	* Nodes definitions and classes.
	* Resource definition and overrides with all parameters.
	* Class includes.
	* Defined variables.

* Parsed information is writen to stdout in YAML format.

## Future Work

* Parse defines.
* Parse class and define parameters.
* RDOC documentation parsing.

## Usage

```
$ puppet-parser/bin/puppet-parser <PATH> [PATH]...
```

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
