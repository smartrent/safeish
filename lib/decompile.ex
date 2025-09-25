defmodule Decompile do
  @moduledoc false

  # Following only since OTP 20
  @tag_extended_list 0b00010111
  # @tag_extended_fp_register 0b00100111
  @tag_extended_allocation_list 0b00110111
  @tag_extended_literal 0b01000111

  defstruct instruction_set: nil,
            number_of_functions: 0,
            number_of_labels: 0,
            opcode_max: 0,
            atoms: [],
            literals: [],
            imports: [],
            exports: [],
            functions: [],
            strings: [],
            code: [],
            opcodes: MapSet.new()

  def decompile(bytecode) do
    case :beam_lib.chunks(
           bytecode,
           [~c"AtU8", ~c"LitT", ~c"ImpT", ~c"ExpT", ~c"FunT", ~c"StrT", ~c"Code"],
           [:allow_missing_chunks]
         ) do
      {:ok,
       {module,
        [
          {~c"AtU8", atoms},
          {~c"LitT", literals},
          {~c"ImpT", imports},
          {~c"ExpT", exports},
          {~c"FunT", functions},
          {~c"StrT", strings},
          {~c"Code", code}
        ]}} ->
        parsed_atoms = parse_atoms(atoms)
        parsed_literals = parse_literals(literals)
        parsed_imports = parse_imports(imports, parsed_atoms)
        parsed_exports = parse_exports(exports, parsed_atoms)
        parsed_functions = parse_functions(functions, parsed_atoms)
        parsed_strings = parse_strings(strings)
        [info | code] = parse_code(code)

        {
          :ok,
          module,
          %{
            info
            | code:
                code
                |> decode_tags(parsed_atoms, parsed_literals)
                |> fix_labels
                |> fix_args(parsed_imports),
              atoms: parsed_atoms,
              literals: parsed_literals,
              imports: parsed_imports,
              exports: parsed_exports,
              functions: parsed_functions,
              strings: parsed_strings,
              opcodes: code |> Keyword.keys() |> Enum.into(MapSet.new())
          }
        }

      err ->
        err
    end
  end

  # Lookups/simplifications at tag level
  def decode_tags([{:tag_u, value} | rest], a, l), do: [value | decode_tags(rest, a, l)]
  def decode_tags([{:tag_i, value} | rest], a, l), do: [value | decode_tags(rest, a, l)]
  def decode_tags([{:tag_a, 0} | rest], a, l), do: [nil | decode_tags(rest, a, l)]

  def decode_tags([{:tag_a, index} | rest], a, l),
    do: [elem(a, index - 1) | decode_tags(rest, a, l)]

  def decode_tags([{:tag_x, index} | rest], a, l), do: [{:x, index} | decode_tags(rest, a, l)]
  def decode_tags([{:tag_y, index} | rest], a, l), do: [{:y, index} | decode_tags(rest, a, l)]
  def decode_tags([{:tag_f, value} | rest], a, l), do: [{:f, value} | decode_tags(rest, a, l)]

  def decode_tags([{:tag_h, c} | rest], a, l),
    do: [String.next_codepoint(c) | decode_tags(rest, a, l)]

  def decode_tags([{:tag_extended_literal, index} | rest], a, l),
    do: [elem(l, index) | decode_tags(rest, a, l)]

  def decode_tags([{:tag_extended_list, list} | rest], a, l),
    do: [decode_tags(list, a, l) | decode_tags(rest, a, l)]

  def decode_tags([{key, value} | rest], a, l) when is_atom(key),
    do: [{key, decode_tags(value, a, l)} | decode_tags(rest, a, l)]

  def decode_tags([x | rest], a, l), do: [decode_tags(x, a, l) | decode_tags(rest, a, l)]
  def decode_tags([], _, _), do: []
  def decode_tags(x, _, _), do: x

  # Neaten up line numbers and labels
  def fix_labels([{:line, [0]} | rest]), do: [{:line, []} | fix_labels(rest)]
  def fix_labels([{:line, [x]} | rest]), do: [{:line, x} | fix_labels(rest)]

  def fix_labels([{:label, [num]} | rest]) when is_number(num),
    do: [{:label, num} | fix_labels(rest)]

  def fix_labels([x | rest]), do: [fix_labels(x) | fix_labels(rest)]
  def fix_labels([]), do: []
  def fix_labels(x), do: x

  # Opcode specific argument lookups, this information lost in compilation
  # TO DO extremely incomplete...
  def fix_args({:call_ext, [arity, dest]}, imports), do: {:call_ext, [arity, elem(imports, dest)]}

  def fix_args({:call_ext_only, [arity, dest]}, imports),
    do: {:call_ext_only, [arity, elem(imports, dest)]}

  def fix_args({:call_ext_last, [arity, dest, dealloc]}, imports),
    do: {:call_ext_only, [arity, elem(imports, dest), dealloc]}

  def fix_args({:bif0, [bif, register]}, imports), do: {:bif0, [elem(imports, bif), register]}

  def fix_args({:gc_bif1, [label, live, bif | rest]}, imports),
    do: {:gc_bif1, [label, live, elem(imports, bif) | rest]}

  def fix_args({:gc_bif2, [label, live, bif | rest]}, imports),
    do: {:gc_bif2, [label, live, elem(imports, bif) | rest]}

  def fix_args({:gc_bif3, [label, live, bif | rest]}, imports),
    do: {:gc_bif3, [label, live, elem(imports, bif) | rest]}

  def fix_args([x | rest], imports), do: [fix_args(x, imports) | fix_args(rest, imports)]
  def fix_args([], _), do: []
  def fix_args(x, _), do: x

  def parse_atoms(<<atom_count::integer-size(32), atoms::binary>>) do
    parse_atoms(atoms, atom_count, [])
  end

  def parse_atoms(_, 0, names), do: names |> Enum.reverse() |> List.to_tuple()

  def parse_atoms(
        <<length::integer, name::binary-size(length), atoms::binary>>,
        atoms_remaining,
        names
      ) do
    parse_atoms(atoms, atoms_remaining - 1, [String.to_atom(name) | names])
  end

  def parse_literals(:missing_chunk), do: {}

  def parse_literals(<<_compressed_table_size::integer-size(32), compressed::binary>>) do
    <<_number_of_literals::integer-size(32), table::binary>> = :zlib.uncompress(compressed)
    parse_literals(table, [])
  end

  def parse_literals(<<>>, literals), do: literals |> Enum.reverse() |> List.to_tuple()

  def parse_literals(
        <<size::integer-size(32), literal::binary-size(size), rest::binary>>,
        literals
      ) do
    parse_literals(rest, [:erlang.binary_to_term(literal) | literals])
  end

  def parse_imports(:missing_chunk), do: {}

  def parse_imports(<<_number_of_imports::integer-size(32), table::binary>>, atoms) do
    parse_imports(table, atoms, [])
  end

  def parse_imports(table, _, imports) when byte_size(table) < 4,
    do: imports |> Enum.reverse() |> List.to_tuple()

  def parse_imports(
        <<module::integer-size(32), function::integer-size(32), arity::integer-size(32),
          rest::binary>>,
        atoms,
        imports
      ) do
    parse_imports(rest, atoms, [
      {elem(atoms, module - 1), elem(atoms, function - 1), arity} | imports
    ])
  end

  def parse_exports(:missing_chunk, _), do: {}

  def parse_exports(<<_number_of_exports::integer-size(32), table::binary>>, atoms) do
    parse_exports(table, atoms, [])
  end

  def parse_exports(<<>>, _, exports), do: exports |> Enum.reverse() |> List.to_tuple()

  def parse_exports(
        <<function::integer-size(32), arity::integer-size(32), label::integer-size(32),
          rest::binary>>,
        atoms,
        exports
      ) do
    parse_exports(rest, atoms, [{elem(atoms, function - 1), arity, {:label, label}} | exports])
  end

  def parse_functions(:missing_chunk, _), do: {}

  def parse_functions(<<_number_of_functions::integer-size(32), table::binary>>, atoms) do
    parse_functions(table, atoms, [])
  end

  def parse_functions(<<>>, _, functions), do: functions |> Enum.reverse() |> List.to_tuple()

  def parse_functions(
        <<function::integer-size(32), arity::integer-size(32), offset::integer-size(32),
          index::integer-size(32), n_free::integer-size(32), o_uniq::integer-size(32),
          rest::binary>>,
        atoms,
        functions
      ) do
    parse_functions(rest, atoms, [
      {elem(atoms, function - 1), arity, offset, index, n_free, o_uniq} | functions
    ])
  end

  def parse_strings(:missing_chunk), do: ""
  # TO DO How are they separated?
  def parse_strings(strings), do: strings

  def parse_code(<<_sub_size::integer-size(32), chunk::binary>>) do
    <<
      instruction_set::integer-size(32),
      opcode_max::integer-size(32),
      number_of_labels::integer-size(32),
      number_of_functions::integer-size(32),
      opcodes::binary
    >> = chunk

    parse_code(
      opcodes,
      [
        %Decompile{
          number_of_functions: number_of_functions,
          number_of_labels: number_of_labels,
          opcode_max: opcode_max,
          instruction_set: instruction_set
        }
      ]
    )
  end

  def parse_code(remaining, decoded) when byte_size(remaining) < 4 do
    Enum.reverse(decoded)
  end

  def parse_code(<<opcode::integer, rest::binary>>, decoded) do
    {name, arity} = :beam_opcodes.opname(opcode)
    {rest_after_args, args} = parse_compact_terms(rest, arity, [])
    parse_code(rest_after_args, [{name, args} | decoded])
  end

  def parse_compact_terms(rest, 0, parsed_terms), do: {rest, Enum.reverse(parsed_terms)}

  def parse_compact_terms(
        <<value::integer-size(4), 0::integer-size(1), tag::integer-size(3), rest::binary>>,
        remaining_terms,
        parsed_terms
      )
      when tag < 7 do
    parse_compact_terms(rest, remaining_terms - 1, [{decode_tag(tag), value} | parsed_terms])
  end

  def parse_compact_terms(
        <<value_msb::integer-size(3), 0b01::integer-size(2), tag::integer-size(3),
          value_lsb::integer-size(8), rest::binary>>,
        remaining_terms,
        parsed_terms
      )
      when tag < 7 do
    parse_compact_terms(rest, remaining_terms - 1, [
      {decode_tag(tag), value_lsb + value_msb * 512} | parsed_terms
    ])
  end

  def parse_compact_terms(
        <<size_minus_2::integer-size(3), 0b11::integer-size(2), tag::integer-size(3),
          rest::binary>>,
        remaining_terms,
        parsed_terms
      )
      when tag < 7 do
    size = (size_minus_2 + 2) * 8
    <<value::signed-integer-size(size), rest_after_value::binary>> = rest

    parse_compact_terms(rest_after_value, remaining_terms - 1, [
      {decode_tag(tag), value} | parsed_terms
    ])
  end

  def parse_compact_terms(
        <<0b11111::integer-size(5), tag::integer-size(3), rest::binary>>,
        remaining_terms,
        parsed_terms
      )
      when tag < 7 do
    {rest_after_size, [{:tag_u, size_minus_9}]} = parse_compact_terms(rest, 1, [])
    size = (size_minus_9 + 9) * 8
    <<value::signed-integer-size(size), rest_after_value::binary>> = rest_after_size

    parse_compact_terms(rest_after_value, remaining_terms - 1, [
      {decode_tag(tag), value} | parsed_terms
    ])
  end

  def parse_compact_terms(<<@tag_extended_list, rest::binary>>, remaining_terms, parsed_terms) do
    {rest_after_length, [{:tag_u, list_length}]} = parse_compact_terms(rest, 1, [])
    {rest_after_list, terms} = parse_compact_terms(rest_after_length, list_length, [])
    pairs = terms |> Enum.chunk_every(2)

    parse_compact_terms(rest_after_list, remaining_terms - 1, [
      {:tag_extended_list, pairs} | parsed_terms
    ])
  end

  def parse_compact_terms(
        <<@tag_extended_allocation_list, rest::binary>>,
        remaining_terms,
        parsed_terms
      ) do
    {rest_after_length, [{:tag_u, list_length}]} = parse_compact_terms(rest, 1, [])
    {rest_after_list, terms} = parse_compact_terms(rest_after_length, list_length, [])

    parse_compact_terms(rest_after_list, remaining_terms - 1, [
      {:tag_extended_allocation_list, terms} | parsed_terms
    ])
  end

  def parse_compact_terms(<<@tag_extended_literal, rest::binary>>, remaining_terms, parsed_terms) do
    {rest_after_index, [{:tag_u, index}]} = parse_compact_terms(rest, 1, [])

    parse_compact_terms(rest_after_index, remaining_terms - 1, [
      {:tag_extended_literal, index} | parsed_terms
    ])
  end

  # TO DO rest of TBB section 6.2.14, probably decoding negative numbers wrong too.
  #
  # TO DO see https://github.com/erlang/otp/blob/master/lib/compiler/src/beam_asm.erl

  # literal
  def decode_tag(0), do: :tag_u
  # integer
  def decode_tag(1), do: :tag_i
  # atom
  def decode_tag(2), do: :tag_a
  # X register
  def decode_tag(3), do: :tag_x
  # Y register
  def decode_tag(4), do: :tag_y
  # label
  def decode_tag(5), do: :tag_f
  # character
  def decode_tag(6), do: :tag_h
end
