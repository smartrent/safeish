defmodule Safeish do
  @moduledoc """
  NOT FOR PRODUCTION USE

  Safe-ish is an _experimental_, minimally restrictive sandbox for BEAM modules
  that examines and rejects BEAM bytecode at load time containing instructions
  that could cause side effects such as:
  
  - Spawning processes
  - Sending and receiving messages
  - File system access
  - Network access
  - Compilation
  - System level commands, introspection and diagnostics
  - Apply and creating atoms dynamically at runtime (which would allow calls to non-whitelisted modules)
  
  You can provide an optional whitelist of modules, functions and language features that the
  loaded module is allowed to use.
  """
  
  # Following lists were compiled for Elixir 1.10.4 and OTP release 23
  
  
  # Skipped beam_lib, c, dets, digraph, digraph_utils, epp, erl_anno, erl_eval, erl_expand_records,
  # erl_id_trans, erl_internal, erl_lint, erl_parse, erl_scan, erl_tar, ets, file_sorter, file_lib,
  # gen_event, gen_fsm, gen_server, gen_statem, io, io_lib, ms_transform, pool, proc_lib, qlc, shell
  # shell_default, shell_docs, slave, supervisor, supervisor_bridge, sys, win32reg, zip
  @whitelisted_erlang_modules MapSet.new([
    :array, :base64, :binary, :calendar, :dict, :erl_pp, :filename, :gb_sets, :gb_trees, :lists, :maps,
    :math, :orddict, :ordsets, :proplists, :queue, :rand, :re, :sets, :sofs, :string, :unicode,
    :uri_string
  ])
  
  # Note we're allowing access to the process dictionary
  @whitelisted_erlang_functions MapSet.new([
    {:erlang, :+, 2},
    {:erlang, :-, 2},
    {:erlang, :/, 2},
    {:erlang, :*, 2},
    {:erlang, :abs, 1},
    {:erlang, :adler32, 1},
    {:erlang, :adler32, 2},
    {:erlang, :adler32_combine, 3},
    {:erlang, :append_element, 2},
    # skip apply
    {:erlang, :atom_to_binary, 1},
    {:erlang, :atom_to_binary, 2},
    {:erlang, :atom_to_list, 1},
    {:erlang, :binary_part, 2},
    {:erlang, :binary_part, 3},
    # skip binary_to_atom
    {:erlang, :binary_to_float, 1},
    {:erlang, :binary_to_integer, 1},
    {:erlang, :binary_to_integer, 2},
    {:erlang, :binary_to_list, 1},
    {:erlang, :binary_to_list, 3},
    # skip binary_to_term
    {:erlang, :bit_size, 1},
    {:erlang, :bitstring_to_list, 1},
    # skip bump_reductions
    {:erlang, :byte_size, 1},
    # skip cancel_timer
    {:erlang, :ceil, 1},
    {:erlang, :check_old_code, 1},
    {:erlang, :check_process_code, 2},
    {:erlang, :check_process_code, 3},
    {:erlang, :convert_time_unit, 3},
    {:erlang, :crc32, 1},
    {:erlang, :crc32, 2},
    {:erlang, :crc32_combine, 3},
    {:erlang, :date, 0},
    {:erlang, :decode_packet, 3},
    {:erlang, :delete_element, 2},
    # skip delete_module, demonitor, disconnect_node
    {:erlang, :display, 1},
    {:erlang, :div, 2},
    # skip dist_ctrl_*
    {:erlang, :element, 2},
    {:erlang, :erase, 0},
    {:erlang, :erase, 1},
    # skip error, exit
    {:erlang, :external_size, 1},
    {:erlang, :external_size, 2},
    {:erlang, :float, 1},
    {:erlang, :float_to_binary, 1},
    {:erlang, :float_to_binary, 2},
    {:erlang, :float_to_list, 1},
    {:erlang, :float_to_list, 2},
    {:erlang, :floor, 1},
    {:erlang, :fun_info, 1},  # safe without apply()?
    {:erlang, :fun_info, 2},
    {:erlang, :fun_to_list, 1},
    {:erlang, :function_exported, 3},
    # skip garbage_collect
    {:erlang, :get, 0},
    {:erlang, :get, 1},
    # skip get_cookie, security risk (I mean, even too much for Safe-ish)
    {:erlang, :get_keys, 0},
    {:erlang, :get_keys, 1},
    {:erlang, :get_module_info, 1},
    {:erlang, :get_module_info, 2},
    # skip get_stacktrace, deprecated,
    # skip group_leader, halt
    {:erlang, :hd, 1},
    # skip hibernate
    {:erlang, :insert_element, 3},
    {:erlang, :integer_to_binary, 1},
    {:erlang, :integer_to_binary, 2},
    {:erlang, :integer_to_list, 1},
    {:erlang, :integer_to_list, 2},
    {:erlang, :iolist_size, 1},
    {:erlang, :iolist_to_binary, 1},
    {:erlang, :iolist_to_iovec, 1},
    {:erlang, :is_alive, 0},
    {:erlang, :is_atom, 1},
    {:erlang, :is_binary, 1},
    {:erlang, :is_bitstring, 1},
    {:erlang, :is_boolean, 1},
    {:erlang, :is_builtin, 3},
    {:erlang, :is_float, 1},
    {:erlang, :is_function, 1},
    {:erlang, :is_function, 2},
    {:erlang, :is_integer, 1},
    {:erlang, :is_list, 1},
    {:erlang, :is_map, 1},
    {:erlang, :is_map_key, 2},
    {:erlang, :is_number, 1},
    {:erlang, :is_pid, 1},
    {:erlang, :is_port, 1},
    {:erlang, :is_process_alive, 1},
    {:erlang, :is_record, 2},
    {:erlang, :is_record, 3},
    {:erlang, :is_tuple, 1},
    {:erlang, :length, 1},
    # skip link, list_to_atom
    {:erlang, :list_to_binary, 1},
    {:erlang, :list_to_bitstring, 1},
    # skip list_to_existing_atom
    {:erlang, :list_to_float, 1},
    {:erlang, :list_to_integer, 1},
    {:erlang, :list_to_integer, 2},
    # skip list_to_pid, list_to_port
    {:erlang, :list_to_ref, 1},
    {:erlang, :list_to_tuple, 1},
    # skip load_module, load_nif
    {:erlang, :loaded, 0}, # safe without apply?
    {:erlang, :localtime, 0},
    {:erlang, :localtime_to_universaltime, 1},
    {:erlang, :localtime_to_universaltime, 2},
    {:erlang, :make_ref, 0},
    {:erlang, :make_tuple, 2},
    {:erlang, :make_tuple, 3},
    {:erlang, :map_get, 2},
    {:erlang, :map_size, 1},
    # skip match_spec_test, seems to be ets specific
    {:erlang, :max, 2},
    {:erlang, :md5, 1},
    {:erlang, :md5_final, 1},
    {:erlang, :md5_init, 0},
    {:erlang, :md5_update, 2},
    {:erlang, :memory, 0},    # read only, seems safe, no access to contents
    {:erlang, :memory, 1},
    {:erlang, :min, 2},
    # skip module_loaded, monitor, monitor_*
    {:erlang, :monotonic_time, 0},
    {:erlang, :monotonic_time, 1},
    # skip nif_error
    {:erlang, :node, 0},
    {:erlang, :node, 1},
    # skip now, deprecated
    # skip open_port
    {:erlang, :phash, 2},
    {:erlang, :phash2, 1},
    {:erlang, :phash2, 2},
    {:erlang, :pid_to_list, 1},
    # skip port_*, ports
    {:erlang, :pre_loaded, 0},
    # skip process_*, processes, purge_module
    {:erlang, :put, 2},
    # skip raise
    {:erlang, :read_timer, 1},
    # skip read_timer/2 as it allows async we can't receive messages
    {:erlang, :ref_to_list, 1},
    # skip register, registered, resume_process
    {:erlang, :rem, 2},
    {:erlang, :round, 1},
    {:erlang, :self, 0},  # not much use, can't hurt?
    # skip send, send_*, set_cookie
    {:erlang, :setelement, 3},
    {:erlang, :size, 1},
    # skip spawn, spawn_*
    {:erlang, :split_binary, 2},
    # skip start_timer, statistics, suspend_process, system_* except for
    {:erlang, :system_time, 0},
    {:erlang, :system_time, 1},
    {:erlang, :term_to_binary, 1},
    {:erlang, :term_to_binary, 2},
    {:erlang, :term_to_iovec, 1},
    {:erlang, :term_to_iovec, 2},
    {:erlang, :throw, 1},
    {:erlang, :time, 0},
    {:erlang, :time_offset, 0},
    {:erlang, :time_offset, 1},
    {:erlang, :timestamp, 0},
    {:erlang, :tl, 1},
    # skip trace, trace_*
    {:erlang, :trunc, 1},
    {:erlang, :tuple_size, 1},
    {:erlang, :tuple_to_list, 1},
    {:erlang, :unique_integer, 0},
    {:erlang, :unique_integer, 1},
    {:erlang, :universal_time, 0},
    {:erlang, :universal_time_to_local_time, 1},
    # skip unlink, unregister, whereis, yield
    
    # skip apply_*
    {:timer, :cancel, 1},
    # skip exit_*
    {:timer, :hms, 3},
    {:timer, :hours, 1},
    # skip kill_after /1 /2
    {:timer, :minutes, 1},
    {:timer, :now_diff, 2},
    {:timer, :seconds, 1},
    # skip send_*
    {:timer, :sleep, 1},
    {:timer, :tc, 1},
    {:timer, :tc, 2}
    # skip tc/3 with module argument
  ])
  
  
  # Skipped modules with problem functions: Function, Module, String, IO (:stdio/:stderr are problem),
  # Agent, Application, Config, Config.Provider, Config.Reader, DynamicSupervisor, GenServer, Node,
  # Process, Registry, Supervisor, Task, Task.Supervisor, Code, Kernel.ParallelCompiler, Macro, Macro.Env
  # Assume all Kernel.* inlined as erlang in bytecode TODO confirm
  @whitelisted_elixir_modules MapSet.new([
    Atom, Base, Bitwise, Date, DateTime, Exception, Float, Integer, NaiveDateTime, Record, Regex,
    Time, Tuple, URI, Version, Version.Requirement, Access, Date.Range, Enum, Keyword, Map,
    MapSet, Range, Stream, OptionParser, Path, StringIO, Calendar, Calendar.ISO, Calendar.TimeZoneDatabase,
    Calendar.UTCOnlyTimeZoneDatabase, Collectable, Enumerable, Inspect, Inspect.Algebra, Inspect.Opts,
    List.Chars, Protocol, String.Chars, BadFunctionError, BadMapError, BadStructError, CaseClauseError,
    Code.LoadError, CompileError, CondClauseError, Enum.EmptyError, Enum.OutOfBoundsError, ErlangError,
    File.CopyError, File.Error, File.LinkError, File.RenameError, FunctionClauseError, IO.StreamError,
    Inspect.Error, KeyError, MatchError, Module.Types.Error, OptionParser.ParseError, Protocol.UndefinedError,
    Regex.CompileError, RuntimeError, SyntaxError, SystemLimitError, TokenMissingError, TryClauseError,
    UndefinedFunctionError, UnicodeConversionError, Version.InvalidRequirementError, Version.InvalidVersionError,
    WithClauseError
  ])
  
  # Explicitly list safe functions in skipped modules
  @whitelisted_elixir_functions MapSet.new([
  
    # Can't allow Function.capture() TODO or check for literal safe arguments to function capture
    {Function, :identity, 1},
    {Function, :info, 1},

    # Can't allow List.to_atom(), List.to_existing_atom()
    {List, :ascii_printable?, 2},
    {List, :delete, 2},
    {List, :delete_at, 2},
    {List, :duplicate, 2},
    {List, :first, 1},
    {List, :flatten, 1},
    {List, :flatten, 2},
    {List, :foldl, 3},
    {List, :foldr, 3},
    {List, :improper?, 1},
    {List, :insert_at, 3},
    {List, :keydelete, 3},
    {List, :keyfind, 4},
    {List, :keymember?, 3},
    {List, :keyreplace, 4},
    {List, :keysort, 2},
    {List, :keystore, 4},
    {List, :keytake, 3},
    {List, :last, 1},
    {List, :myers_difference, 2},
    {List, :myers_difference, 3},
    {List, :pop_at, 3},
    {List, :replace_at, 3},
    {List, :starts_with?, 2},
    {List, :to_charlist, 1},
    {List, :to_float, 1},
    {List, :to_integer, 1},
    {List, :to_integer, 2},
    {List, :to_string, 1},
    {List, :to_tuple, 1},
    {List, :update_at, 3},
    {List, :wrap, 1},
    {List, :zip, 1},
  
    # Can't allow String.to_atom(), String.to_existing_atom()
    {String, :at, 2},
    {String, :bag_distance, 2},
    {String, :capitalize, 2},
    {String, :chunk, 2},
    {String, :codepoints, 1},
    {String, :contains?, 2},
    {String, :downcase, 2},
    {String, :duplicate, 2},
    {String, :ends_with?, 2},
    {String, :equivalent?, 2},
    {String, :first, 1},
    {String, :graphemes, 1},
    {String, :jaro_distance, 2},
    {String, :last, 1},
    {String, :length, 1},
    {String, :match?, 2},
    {String, :myers_difference, 2},
    {String, :next_codepoint, 1},
    {String, :next_grapheme, 2},
    {String, :next_grapheme_size, 1},
    {String, :normalize, 2},
    {String, :pad_leading, 3},
    {String, :pad_trailing, 2},
    {String, :printable?, 2},
    {String, :replace, 4},
    {String, :replace_leading, 3},
    {String, :replace_prefix, 3},
    {String, :replace_suffix, 3},
    {String, :replace_trailing, 3},
    {String, :reverse, 1},
    {String, :slice, 2},
    {String, :slice, 3},
    {String, :split, 1},
    {String, :split, 2},
    {String, :split, 3},
    {String, :split_at, 2},
    {String, :splitter, 3},
    {String, :starts_with?, 2},
    {String, :to_charlist, 1},
    {String, :to_float, 1},
    {String, :to_integer, 1},
    {String, :to_integer, 2},
    {String, :trim, 1},
    {String, :trim, 2},
    {String, :trim_leading, 1},
    {String, :trim_leading, 2},
    {String, :trim_trailing, 1},
    {String, :trim_trailing, 2},
    {String, :upcase?, 2},
    {String, :valid?, 1},

    # Safe System functions
    {System, :build_info, 0},
    {System, :compiled_endianness, 0},
    {System, :convert_time_unit, 3},
    {System, :endianness, 0},
    {System, :monotonic_time, 0},
    {System, :monotonic_time, 1},
    {System, :os_time, 0},
    {System, :os_time, 1},
    {System, :otp_release, 0},
    {System, :schedulers, 0},
    {System, :schedulers_online, 0},
    {System, :system_time, 0},
    {System, :system_time, 1},
    {System, :time_offset, 0},
    {System, :time_offset, 1},
    {System, :unique_integer, 1},
    {System, :version, 0}
  ])
  
  
  @doc """
  Check and load module bytecode from a file path
  
  ## Params
  filename:         Path to beam file to check and load if content "safe"
  whitelist:        A list of call targets and language features allowed in the bytecode:
                    - Module
                    - {Module, :function}
                    - {Module, :function, arity}
                    - :send
                    - :receive

  ## Examples
  ```
    iex> Safeish.load_bytecode(<<...>>, [WhitelistedModuleA, {WhitelistedModuleB, :some_func}])
    {:ok, SomeSafeModule}
    iex> SomeSafeModule.func()
  ```
  """
  
  
  def load_file(filename, whitelist \\ []) do
    {:ok, file} = File.open(filename, [:read])
    bytecode = IO.binread(file, :all)
    File.close(file)
    load_bytecode(bytecode, whitelist)
  end
  

  @doc """
  Check and load binary module bytecode
  
  ## Params
  bytecode:         Bytecode of module to check and load if content "safe"
  whitelist:        A list of call targets and language features allowed in the bytecode:
                    - Module
                    - {Module, :function}
                    - {Module, :function, arity}
                    - :send
                    - :receive

  ## Examples
  ```
    iex> Safeish.load_bytecode(<<...>>, [WhitelistedModuleA, {WhitelistedModuleB, :some_func}])
    {:ok, SomeSafeModule}
    iex> SomeSafeModule.func()
  ```
  """
  def load_bytecode(bytecode, whitelist \\ []) do
    case check(bytecode, whitelist) do
      {:ok, module} ->
        :code.load_binary(module, module, bytecode)
        {:ok, module}
      error ->
        error
    end
  end
  
  
  @doc """
  Check binary module bytecode
  
  ## Params
  bytecode:         Bytecode of module to check and load if content "safe"
  whitelist:        A list of call targets and language features allowed in the bytecode:
                    - Module
                    - {Module, :function}
                    - {Module, :function, arity}
                    - :send
                    - :receive

  ## Examples
  ```
    iex> Safeish.load_bytecode(<<...>>, [WhitelistedModuleA, {WhitelistedModuleB, :some_func}])
    {:ok, SomeSafeModule}
  ```
  """
  def check(bytecode, whitelist \\ []) do
    {:ok, module, risks} = module_risks(bytecode)
    check_list = risks |> Enum.map(&risk_acceptable?(&1, whitelist))
    if Enum.all?(check_list, &match?(:ok, &1)) do
      {:ok, module}
    else
      {:error, module, check_list
                        |> Enum.filter(&match?({:error, _}, &1))
                        |> Enum.map(fn {:error, msg} -> msg end)}
    end
  end
  
  
  def risk_acceptable?({module, _, _}, [module | _whitelist]), do: :ok
  def risk_acceptable?({module, function, _}, [{module, function} | _whitelist]), do: :ok
  def risk_acceptable?(mfa, [mfa | _whitelist]), do: :ok
  def risk_acceptable?(:remove_message, [:receive | _whitelist]), do: :ok
  def risk_acceptable?({:erlang, :send, 2}, [:send | _whitelist]), do: :ok
  def risk_acceptable?(risk, [_not_that_risk | whitelist]), do: risk_acceptable?(risk, whitelist)
  
  def risk_acceptable?(mfa = {module, function, arity}, []) do
    if MapSet.member?(@whitelisted_erlang_modules, module) or
       MapSet.member?(@whitelisted_elixir_modules, module) or
       MapSet.member?(@whitelisted_erlang_functions, mfa) or
       MapSet.member?(@whitelisted_elixir_functions, mfa) do
      :ok
    else
      m = Atom.to_string(module)
      f = Atom.to_string(function)
      a = Integer.to_string(arity)
      {
        :error,
        "#{if String.match?(m, ~r/^[a-z]/) do ":" else "" end}#{m}.#{f}/#{a} not whitelisted"
      }
    end
  end
    
  def risk_acceptable?(:remove_message, []) do
    {:error, "receive (remove_message) not allowed"}
  end
  
  def risk_acceptable?(:apply, []) do
    {:error, "apply not allowed"}
  end
    
  def risk_acceptable?(_, _), do: :ok
  
  
  # TODO detect __STACKTRACE__/0, non literal apply arguments
  
  def module_risks(bytecode) when is_binary(bytecode) do
    case Decompile.decompile(bytecode) do
      {:ok, module, %Decompile{imports: imports, opcodes: opcodes}} ->
        {:ok,
          module,
          Enum.into(Tuple.to_list(imports), opcodes)}
      error ->
        error
    end
  end
  
end
