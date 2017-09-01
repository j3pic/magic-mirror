# How to Use This Project to Map Your Database

## Make sure your default version of Ruby matches your project's
   version.

If you're using RBENV, that means the version in `~/.ruby-version` matches what's
in your project's `.ruby-version`. I don't know how RVM works, though.

## Launch a Rails console using `magic-rails.sh`

    magic-rails.sh console

This loads the MagicMirror introspection tool first, and then loads Rails.

## Load `database-mapper.rb`

    require '/path/to/database-mapper.rb'

This part takes a while. The database-mapper will:

1. Force-load all the code it can from your `$LOAD_PATH`. This gets your entire app
into memory up front instead of waiting for Rails to autoload it upon reference.
2. Walk the `~/carrot` directory and force-load everything it finds in every directory
named `models`. This will get most of the ActiveRecord models in Instacart into memory.
3. Search for database connections. It does this by traversing all the classes it loaded.
4. Build the `MODELS` index.
4. Build the `FOREIGN_KEY_MAP`. This structure contains a detailed map of the DB, including
errors.

## Create the database-map.json file.

    [2] pry(main)> save_database_map(build_database_map, "/tmp/database-map.json")

The JSON file will show all the tables that have models, and all the foreign keys
that those tables have, and which tables those keys point to. In the case of
certain polymorphic associations, the foreign key appears once for each table it
might point to.

## Review the dead tables.

    MODELS[:unknown-tables] is a list of database tables that Postgres told
    the database mapper about, but the database mapper didn't find a model
    for.

## Other features.

    find_database_model(table_name)

This searches MagicMirror's class index for the ActiveRecord model that represents
the SQL table named by `table_name`.

# MagicMirror - Analyze Ruby and Rails apps with reflection

MagicMirror provides the following capabilities:

## Record and retrieve the source locations of every monkey patch
   that affects a given class.

You can see where your class has been monkey patched, and how many times.
Every class that is defined after MagicMirror has loaded will be tagged
with a `source_locations` attribute. There is also the more detailed
`magic_mirror_source_locations` attribute.

## MagicMirror.apropos

MagicMirror maintains an index of every class and method it has seen. You
can search for these by regexp. For example:

    [432] pry(main)> MagicMirror.apropos /Baz/, match_methods: false
    Foo::Bar::Baz
    Foo::Bar::Baz::BAZ_CONSTANT

`apropos` prints to stdout, while `apropos_data` has the same interface, but
returns an array of strings instead of printing.

## Evaluate code in the context of an existing file.

    MagicMirror.eval_at(file,line,expression)

Recreates the nesting that was seen when the file loaded. Classes and
methods defined this way will appear to have been defined at the
specified file and line, plus whatever lines exist within the `expression`.


