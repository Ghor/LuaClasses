-- The tables 'meta' and 'static' are automatically defined as locals for this script by the class system. Just fill them out to define the class.

-- Locals --------------------------------------------------------------
 
local atan2        = math.atan2
local cos          = math.cos
local deg          = math.deg
local max          = math.max
local min          = math.min
local sin          = math.sin
local sqrt         = math.sqrt
local type         = type

-- Metamethods ---------------------------------------------------------

function meta:__init( x, y )
	self.x, self.y = x or 0, y or 0
end

function meta:__serialize( t )
	t.x=self.x
	t.y=self.y
end

function meta:__copy()
	return static( self.x, self.y )
end

function meta:__assign( other )
	self.x, self.y = other.x, other.y
end
 
function meta:__add( other )
	return static(
		self.x + other.x,
		self.y + other.y
	)
end
 
function meta:__div( scalar )
	if ( type( self )=="number" ) then
		self, scalar = scalar, self
	end
	return static(
		self.x / scalar,
		self.y / scalar
	)
end

function meta:__eq( other )
	return ( self and other and
		( self.x == other.x )
		and ( self.y == other.y )
	)
end
 
function meta:__mul( scalar )
	if ( type( self )=="number" ) then
		self, scalar = scalar, self
	end
	
	return static(
		self.x * scalar,
		self.y * scalar
	)
end
 
function meta:__sub( other )
	return static(
		self.x - other.x,
		self.y - other.y
	)
end
 
function meta:__tostring( )
	return ("Vector2( %s, %s )"):format( self.x, self.y )
end
 
function meta:__unm()
	return static(
		-self.x,
		-self.y
	)
end
 
-- Arithmetic ----------------------------------------------------------
 
function meta:Add( other )
	self.x = self.x + other.x
	self.y = self.y + other.y
end
 
function meta:Sub( other )
	self.x = self.x - other.x
	self.y = self.y - other.y
end
 
function meta:Mul( scalar )
	self.x = self.x * scalar
	self.y = self.y * scalar
end
 
function meta:Div( scalar )
	self.x = self.x / scalar
	self.y = self.y / scalar
end
 
-- Modifiers -----------------------------------------------------------
 
function meta:Negate()
	self.x = -self.x
	self.y = -self.y
end
 
function meta:Normalize()
	local magnitude = self:Magnitude()
	if ( magnitude == 0 ) then
		return
	end
	self.x = self.x / magnitude
	self.y = self.y / magnitude
end

function meta:ClampMagnitude( min_magnitude, max_magnitude )
	local magnitude = self:Magnitude()
	local target_magnitude = magnitude
	target_magnitude = max( min_magnitude, min( target_magnitude, max_magnitude ) )
	if ( magnitude == target_magnitude ) then
		return
	end
	self:Mul( target_magnitude/magnitude )
end

function meta:Translate( translation )
	self:Add( translation )
end

function meta:Scale( scale )
	self.x = self.x * scale.x
	self.y = self.y * scale.y
end

function meta:ScaleDiv( scale )
	self.x = self.x / scale.x
	self.y = self.y / scale.y
end

function meta:Rotate( radians )
	local x = self.x
	local y = self.y
	local c = cos( radians )
	local s = sin( radians )
	self.x = c * x - s * y
	self.y = c * y + s * x
end

function meta:RotateWorld( radians )
	local x = self.x
	local y = self.y
	local c = cos( radians )
	local s = -sin( radians )
	self.x = c * x - s * y
	self.y = c * y + s * x
end

function meta:Set( other )
	self.x = other.x
	self.y = other.y
end

function meta:SetXY( x, y )
	self.x = x
	self.y = y
end

function meta:SetFromString( str )
	local x, y = str:match( "(%-?%d+%.?%d*e?%-?%d*)..-(%-?%d+%.?%d*e?%-?%d*)" )
	x = tonumber( x )
	y = tonumber( y )
	if ( ( not x ) or ( not y ) ) then
		error( ("Attempted to set Vector2 from malformed string %q."):format( str ), 2 )
	end
end
 
function meta:Zero( )
	self.x = 0
	self.y = 0
end
 
-- Scalars -------------------------------------------------------------
 
function meta:Magnitude( )
	return sqrt(
		( self.x ^ 2 )
		+ ( self.y ^ 2 )
	)
end
 
function meta:MagnitudeSqr( )
	return (
		( self.x ^ 2 )
		+ ( self.y ^ 2 )
	)
end
 
function meta:Distance( other )
	return sqrt(
		( ( self.x - other.x ) ^ 2 )
		+ ( ( self.y - other.y ) ^ 2 )
	)
end
 
function meta:DistanceSqr( other )
	return (
		( ( self.x - other.x ) ^ 2 )
		+ ( ( self.y - other.y ) ^ 2 )
	)
end

function meta:DistanceToLine( p1, p2 )
	if ( p1 == p2 ) then
		return self:Distance( p1 )
	end
	local d = p1:Distance( p2 )
	local t = ((self.x - p1.x) * (p2.x - p1.x) + ( self.y - p1.y )*(p2.y - p1.y))/(d*d)
	
	static.temporary:SetXY( p1.x + t*(p2.x-p1.x), p1.y + t*(p2.y-p1.y) )
	return self:Distance( static.temporary )
end

function meta:GetClosestPointOnLine( p1, p2 )
	local diff = p2 - p1
	
	local t = ( self - p1 ):Dot( diff:GetNormalized() )
	return p1 + ( diff:GetNormalized()*t )
	
end
 
function meta:Dot( other )
	return ( self.x * other.x ) + ( self.y * other.y )
end
 
-- Vectors -------------------------------------------------------------
 
function meta:Cross( other )
	return ( self.x * other.y ) - ( self.y * other.x )
end

function meta:GetNormalized( )
	local magnitude = self:Magnitude()
	return static(
		( magnitude == 0 ) and 0 or ( self.x / magnitude ),
		( magnitude == 0 ) and 0 or ( self.y / magnitude )
	)
end
 
-- Angle --------------------------------------------------------------

function meta:Rad()
	return atan2( self.y, self.x )
end

function meta:WorldRad()
	return atan2( -self.y, self.x )
end

function meta:Deg()
	return deg( atan2( self.y, self.x ) )
end

function meta:WorldDeg()
	return deg( atan2( -self.y, self.x ) )
end
 
-- Tests --------------------------------------------------------------
 
function meta:IsZero( )
	return (
		( self.x == 0 )
		and ( self.y == 0 )
	)
end
 
function meta:WithinAABox( mins, maxs )
	return (
	-- Greater than or equal to minimum bounds
	( self.x >= mins.x )
	and ( self.y >= mins.y )
	
	-- Less than or equal to maximum bounds
	and ( self.x <= maxs.x )
	and ( self.y <= maxs.y )
	)
end

function meta:GetXY()
	return self.x, self.y
end

-- Static stuff -----------------------------------------------------

function static.SortMinMax( a, b )
	a.x, b.x = min( a.x, b.x ), max( a.x, b.x )
	a.y, b.y = min( a.y, b.y ), max( a.y, b.y )
end

static.zero = static( 0, 0 )
static.up = static( 0, -1 )
static.down = static( 0, 1 )
static.left = static( -1, 0 )
static.right = static( 1, 0 )
static.temporary = static()

function static.Lerp( fraction, vector_a, vector_b )
	local diff = vector_b - vector_a
	diff:Mul( fraction )
	diff:Add( vector_a )
	return diff
end

function static.Approach( current_vector, target_vector, approach_magnitude )
	local diff = target_vector - current_vector
	if ( diff:GetMagnitude() <= approach_magnitude ) then
		return Assign( diff, target_vector )
	end
	diff:Normalize()
	diff:Mul( approach_magnitude )
	diff:Add( current_vector )
	return diff
end

-- Properties -------------------------------------------------------
-- Most of these properties are pointless aliases, they are mainly here as examples that demonstrate how to create C#-like properties in this class system.

-- Alias for array-like indexing.
Property( 0, { get = function( obj ) return obj.x end, set = function( obj, value ) obj.x = value end } )
Property( 1, { get = function( obj ) return obj.y end, set = function( obj, value ) obj.y = value end } )

-- Alias for texcoord indexing.
Property( "u", { get = function( obj ) return obj.x end, set = function( obj, value ) obj.x = value end } )
Property( "v", { get = function( obj ) return obj.y end, set = function( obj, value ) obj.y = value end } )

-- Read-only property for a normalized copy of the vector.
Property( "normalized", { get = function( obj ) return obj:GetNormalized() end } )

-- Read-only property for the magnitude of the vector.
Property( "magnitude", { get = function( obj ) return obj:Magnitude() end } )