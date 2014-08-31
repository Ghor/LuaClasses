local classes = {}

-------------------
-- Script Loader --
-------------------

local script_loader_func = function( path )
		local code_file = io.open( path )
		if ( not code_file ) then
			return nil
		end
		local code = code_file:read( "*a" )
		code_file:close()
		return code
	end

-- Sets custom behavior for script loading.
-- The given function must translate a file path string to a string of Lua code. The function should return nil on failure.
-- Useful for live-coding integration, or when your project uses something other than the io library for file handling.
function classes.SetCustomScriptLoader( func )
	script_loader_func = func
end

--------------------------------------
-- Identifier and Namespace Helpers --
--------------------------------------

-- Converts a string of nested identifiers into a sequence of the individual identifiers.
-- For example, the string "ui.controls.Button" will return the sequence { "ui", "controls", "Button" }
local function SplitFullyQualifiedName( fully_qualified_name )
	local sequence = {}
	for match in string.gmatch( fully_qualified_name, "([_a-zA-Z][_a-zA-Z0-9]*)%.*" ) do
		table.insert( sequence, match )
	end
	return sequence
end

-- Returns a namespace table from the given name sequence, creating it if it doesn't exist yet.
local function LookupNamespace( namespace_name_sequence )
	local visiting_namespace = _G
	for _, namespace_name in ipairs( namespace_name_sequence ) do
		if ( not visiting_namespace[ namespace_name ] ) then
			visiting_namespace[ namespace_name ] = {}
		end
		visiting_namespace = visiting_namespace[ namespace_name ]
	end
	return visiting_namespace
end

-- Returns a path to the script that defines the named class.
local function GetPathFromClassName( class_name )
	local identifier_sequence = SplitFullyQualifiedName( class_name )
	return "lua/classes/"..table.concat( identifier_sequence, "/" )..".lua"
end

------------------------
-- Table Manipulation --
------------------------

local function ShallowCopy( t )
	local copy_t = {}
	for k,v in pairs( t ) do
		copy_t[ k ] = v
	end
	setmetatable( copy_t, getmetatable( t ) )
	return copy_t
end

local function Clear( t )
	setmetatable( t, nil )
	for k,v in pairs( t ) do
		t[k] = nil
	end
end

local function RemoveByValue( t, v )
	for i=1, #t do
		if ( t[i]==v ) then
			table.remove( t, i )
			return
		end
	end
end

local function CopyTo( src, dest )
	for k,v in pairs( src ) do
		dest[ k ] = v
	end
	setmetatable( dest, getmetatable( src ) )
end

----------------------
-- Class Definition --
----------------------
-- The master list of the class system.
-- 
-- Keyed by the full name of a class, the static table, and the instance metatable, is a "hub", a table that refers to all three and contains further information like inheritance chains, file modification times, and any other metadata that may be required.
local class_catalog = {}

local function CreateClass( full_name )
	
	local name_sequence = SplitFullyQualifiedName( full_name )
	local name = table.remove( name_sequence )
	local namespace = LookupNamespace( name_sequence )
	
	local classinfo = {
		full_name = full_name,
		static = {},
		meta = {},
		properties = {},
		ancestor_classes = {},
		immediate_subclasses = {},
		namespace = namespace
	}
	
	-- The class table should be accessible from its fully-qualified name, its static table, and its metatable.
	class_catalog[ classinfo.full_name ] = classinfo
	class_catalog[ classinfo.static ] = classinfo
	class_catalog[ classinfo.meta ] = classinfo
	
	-- Make the class' static table accessible from its namespace
	namespace[ name ] = classinfo.static
	
	classes.LoadClass( full_name )
end

-- Must take a string.
local function GetClassInfo( full_name )
	if ( not class_catalog[ full_name ] ) then
		CreateClass( full_name )
	end
	return class_catalog[ full_name ]
end

-- Used to ensure the named class is loaded.
function classes.RequireClass( full_name )
	if ( not class_catalog[ full_name ] ) then
		CreateClass( full_name )
	end
end

-- Retrieves the static table of the named class.
function classes.FindClass( meta_static_or_fullname )
	local classinfo = GetClassInfo( meta_static_or_fullname )
	return classinfo and classinfo.static or nil
end

-- Initializes 'classinfo'. A backup table of its state is returned.
local function InitializeClass( classinfo )
	local backup = {}
	backup.meta = ShallowCopy( classinfo.meta )
	backup.static = ShallowCopy( classinfo.static )
	backup.properties = ShallowCopy( classinfo.properties )
	backup.ancestor_classes = ShallowCopy( classinfo.ancestor_classes )
	backup.immediate_subclasses = ShallowCopy( classinfo.immediate_subclasses )
	
	local superclass = classinfo.ancestor_classes[1]
	if ( superclass ) then
		RemoveByValue( superclass.immediate_subclasses, classinfo )
	end
	
	Clear( classinfo.meta )
	Clear( classinfo.static )
	Clear( classinfo.properties )
	Clear( classinfo.ancestor_classes )
	Clear( classinfo.immediate_subclasses )
	
	-- Initialze the class' metatable.
		local meta = classinfo.meta
		
		-- Property access
		local properties = classinfo.properties
		meta.__index = function( obj, key )
			if ( meta[key] ~= nil ) then
				return meta[key]
			end
			return properties[key] and properties[key].get and properties[key].get( obj ) or nil
		end
		meta.__newindex = function( obj, key, value )
			if ( properties[key] ) then
				if ( properties[key].set ) then
					properties[key].set( obj, value )
				end
				return
			end
			rawset( obj, key, value )
		end
		
		-- tostring
		local full_name = classinfo.full_name
		meta.__tostring = function() return full_name end
		
	-- Initialize the class' static table.
		setmetatable( classinfo.static, {
			__call = function( self, ...)
				local obj = setmetatable( {}, meta )
				classes.InvokeMethodAscending( obj, "__init", ... )
				return obj
			end
		} )
	
	return backup
end

-- Restores a class from a backup table.
local function RestoreClass( classinfo, backup )
	CopyTo( classinfo.meta, backup.meta )
	CopyTo( classinfo.static, backup.static )
	CopyTo( classinfo.properties, backup.properties )
	CopyTo( classinfo.ancestor_classes, backup.ancestor_classes )
	CopyTo( classinfo.immediate_subclasses, backup.immediate_subclasses )
	
	-- Store a reference to class as a subclass of superclass. This is mainly only to allow a reloaded class to reload its subclasses.
	local superclassinfo = classinfo.ancestor_classes[1]
	if ( superclassinfo ) then
		table.insert( superclassinfo.immediate_subclasses, classinfo )
	end
end

-- Makes 'classinfo' a child class of 'superclassinfo'
local function Inherit( classinfo, superclassinfo )
	if ( classinfo.ancestor_classes[1] ) then
		error( "Attempted to inherit from more than one parent. Multiple inheritance is not supported.", 2 )
	end
	
	-- Store the chain of inheritance.
	table.insert( classinfo.ancestor_classes, superclassinfo )
	for _, ancestor_class in ipairs( superclassinfo.ancestor_classes ) do
		table.insert( classinfo.ancestor_classes, ancestor_class )
	end
	
	-- We keep the ancestor table reverse-indexable so we can do quicker type checking.
	-- For example, if we want to check if class 'a' descends from class 'b', we only need to check that 'a.superclasses[ b ]' isn't nil.
	for k, v in pairs( classinfo.ancestor_classes ) do
		classinfo.ancestor_classes[ v ] = k
	end
	
	-- Store a reference to class as a subclass of superclass. This is mainly only to allow a reloaded class to reload its subclasses.
	table.insert( superclassinfo.immediate_subclasses, classinfo )
	
	-- Inherit metatable values, static values, and properties.
	for k,v in pairs( superclassinfo.meta ) do
		if ( classinfo.meta[ k ] == nil ) then
			classinfo.meta[ k ] = v
		end
	end
	for k,v in pairs( superclassinfo.static ) do
		if ( classinfo.static[ k ] == nil ) then
			classinfo.static[ k ] = v
		end
	end
	for k,v in pairs( superclassinfo.properties ) do
		if ( classinfo.properties[ k ] == nil ) then
			classinfo.properties[ k ] = v
		end
	end
end

-- Loads a class from a script. If the class has already been defined, it will be reloaded.
function classes.LoadClass( full_name )
	
	-- Load the script code.
	local classinfo = GetClassInfo( full_name )
	if ( not classinfo ) then
		error( string.format( "Class \"%s\" does not exist.", full_name ), 2 )
	end
	
	local script_path = GetPathFromClassName( full_name )
	local script_code = script_loader_func( script_path )
	if ( not script_code ) then
		error( string.format( "Unable to open class definition file for class \"%s\". Path: \"%s\"", full_name, script_path ), 2 )
	end
	
	-- Clear any existing definitions in the class.
	local backup = InitializeClass( classinfo )
	
	-- Prepare the script environment. Changing the global environment is kind of gross, but it's convenient.
	_G.meta = classinfo.meta
	_G.static = classinfo.static
	_G.Inherit = function( superclass_full_name ) Inherit( classinfo, GetClassInfo( superclass_full_name ) ) end
	_G.Property = function( key, property_table )
		classinfo.properties[ key ] = property_table
	end
	script_code = "local static, meta, Inherit, Property = _G.static, _G.meta, _G.Inherit, _G.Property; _G.static, _G.meta, _G.Inherit, _G.Property = nil, nil, nil, nil;"..script_code;
	
	-- Execute the script.
	local ok, msg = pcall( function()
		-- Run the code.
		local code_func, compile_error_msg = loadstring( script_code, script_path )
		if ( not code_func ) then
			print( "Loading error." )
			error( string.format( "Error loading class \"%s\": %s", full_name, compile_error_msg ), 2 )
		end
		local ok, run_error_msg = pcall( code_func )
		if ( not ok ) then
			print( "Execution error." )
			error( string.format( "Error executing class definition \"%s\": %s", full_name, run_error_msg ), 2 )
		end
	end )
	
	-- If something went wrong while trying to load the class, restore it to the backup state and propagate the error.
	if ( not ok ) then
		InitializeClass( classinfo ) -- Strip the class before restoring it from the backup table.
		RestoreClass( classinfo, backup )
		error( msg, 2 )
	end
	
	-- If this was a reload rather than a first load, reload any subclasses.
	for _, subclass in ipairs( backup.immediate_subclasses ) do
		classes.LoadClass( subclass.name )
	end
end

------------------------
-- Instance Functions --
------------------------

-- Returns the class name of an object.
function classes.ClassName( instance )
	if ( type( instance ) == "table" ) then
		local classinfo = class_catalog[ getmetatable( instance ) ]
		return classinfo and classinfo.full_name or "table"
	end
	return type( instance )
end

-- Calls the named method on 'instance', as defined by its class and every ancestor of that class. Think of it like a C++ constructor.
function classes.InvokeMethodDescending( instance, method_name, ... )
	local meta = getmetatable( instance )
	local classinfo = class_catalog[ meta ]
	local ancestor_classes = classinfo.ancestor_classes
	
	local last_func = nil
	for i=1, #ancestor_classes do
		local func = ancestor_classes[i].meta[ method_name ]
		if ( func and ( func ~= last_func ) ) then
			func( instance, ... )
			last_func = func
		end
	end
	if ( meta[ method_name ] and ( meta[ method_name ] ~= last_func ) ) then
		meta[ method_name ]( instance, ... )
	end
end

-- Calls the named method on 'instance', as defined by its class and every ancestor of that class. Think of it like a C++ destructor.
function classes.InvokeMethodAscending( instance, method_name, ... )
	local meta = getmetatable( instance )
	local classinfo = class_catalog[ meta ]
	local ancestor_classes = classinfo.ancestor_classes
	
	local last_func = nil
	if ( meta[ method_name ] and ( meta[ method_name ] ~= last_func ) ) then
		meta[ method_name ]( instance, ... )
		last_func = meta[ method_name ]
	end
	for i=#ancestor_classes, 1, -1 do
		local func = ancestor_classes[i].meta[ method_name ]
		if ( func and ( func ~= last_func ) ) then
			func( instance, ... )
			last_func = func
		end
	end
end

-- Returns true if the object 'instance' is of the class associated with 'static_or_fullname' or any of its ancestor classes. Returns false otherwise.
function classes.Is( instance, static_or_fullname )
	local meta = getmetatable( instance )
	local test_classinfo = class_catalog[ static_or_fullname ]
	if ( class_catalog[ meta ] ) then
		return ( class_catalog[ meta ] == test_classinfo ) or class_catalog[ meta ].ancestor_classes[ test_classinfo ] or false
	end
	return false
end

return classes