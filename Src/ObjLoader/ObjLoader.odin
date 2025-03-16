//A very basic parser for the .obj file format.
//Note that it is very purpose built for this specific project and does not fully implement everything
//that the .obj file format supports.
//It contains some basic error reporting but was not extensively tested on invalid input.
package obj_loader

import "core:strconv"
import "core:mem/virtual"
import "core:log"
import scan "core:text/scanner"
import arr "core:container/small_array"

Coord    :: [4]f32
TexCoord :: [3]f32
Normal   :: [3]f32

IndexType :: int

Vertex :: struct {
  Coord   : IndexType,
  TexCoord: IndexType,
  Normal  : IndexType,
}

Face :: [3]Vertex

Object :: struct {
  Coords    : [dynamic]Coord,
  TexCoords : [dynamic]Normal,
  Normals   : [dynamic]TexCoord,
  Faces     : [dynamic]Face,
}

Match :: proc(scanner: ^scan.Scanner, tok: rune, error: string = "") -> bool {
  peeked := scan.peek_token(scanner)
  if peeked == tok {
    scan.scan(scanner)
    return true
  }
  else {
    if len(error) > 0 do log.error(error)
    return false
  }
}

MatchFloat :: proc(scanner: ^scan.Scanner, error: string = "") -> (val: f32, success: bool) {
  peeked := scan.peek_token(scanner)
  sign: f32 = 1
  if (peeked == '-' || peeked == '+') {
    sign = peeked == '-' ? -1 : 1
    scan.scan(scanner)
  } 
  
  peeked = scan.peek_token(scanner)
  if peeked == scan.Float {
    scan.scan(scanner)
    tok_str := scan.token_text(scanner)
    v, err := strconv.parse_f32(tok_str)
    return v * sign, err
  }
  else {
    if len(error) > 0 do log.error(error)
    return 0, false
  }
}

LoadFromMemory :: proc(arena: ^virtual.Arena, data: string) -> (Object, bool) {
  context.allocator = virtual.arena_allocator(arena)
  
  obj: Object
  
  scanner: scan.Scanner
  scan.init(&scanner, data)
  
  Whitespace0 :: scan.Whitespace{'\t', '\n', '\r', ' '}
  Whitespace1 :: scan.Whitespace{'\t', '\r', ' '}
  Tokens :: scan.Scan_Flags{ .Scan_Ints, .Scan_Floats, .Scan_Chars, }
  
  scanner.whitespace = Whitespace0
  scanner.flags = Tokens
  
  for tok := scan.scan(&scanner); tok != scan.EOF; tok = scan.scan(&scanner) {
    switch tok {
      case 'v':
        if Match(&scanner, 't') {
          tex_coord: TexCoord
          for &t, i in tex_coord {
            optional := i > 1
            if v, ok := MatchFloat(&scanner, optional ? "" : "'vt' must be followed by exactly 2 or 3 vertex coordinates"); ok {
              t = v
            }
            else if !optional do return obj, false
          }
          append(&obj.TexCoords, tex_coord)
        }
        else if Match(&scanner, 'n') {
          normal: TexCoord
          for &n in normal {
            if v, ok := MatchFloat(&scanner, "'vn' must be followed by exactly 3 vertex coordinates"); ok {
              n = v
            }
            else do return obj, false
          }   
          append(&obj.Normals, normal)
        }
        else {
          coord: Coord
          for &c, i in coord {
            optional := i > 1
            if v, ok := MatchFloat(&scanner, optional ? "" : "'v' must be followed by exactly 3 or 4 vertex coordinates"); ok {
              c = v
            }
            else if !optional do return obj, false
          }        
          append(&obj.Coords, coord)
        }
        
      case 'f':
        vertices: arr.Small_Array(3, Vertex)
        for i in 0..<arr.cap(vertices) {
          v: Vertex
          if Match(&scanner, scan.Int, "'f' must be followed by exactly 3 faces") {
            v.Coord, _ = strconv.parse_int(scan.token_text(&scanner))
            if !Match(&scanner, '/') do continue
          } 
          else do return obj, false
          
          if Match(&scanner, scan.Int) {
            v.TexCoord, _ = strconv.parse_int(scan.token_text(&scanner))
            if !Match(&scanner, '/') do continue
          } 
          else if !Match(&scanner, '/', "'/' must be followed by an index or another '/' if the index should be skipped") do return {}, false
          
          if Match(&scanner, scan.Int, "Expected third index after '/'") {
            v.Normal, _ = strconv.parse_int(scan.token_text(&scanner))
          } 
          else do return obj, false
          
          arr.push(&vertices, v)
        }
        
        face: Face
        copy(face[:], arr.slice(&vertices)[:vertices.len])
        append(&obj.Faces, face)
        
      case:
        log.warnf("Skipped line starting with '%v'. Not supported", scan.token_text(&scanner))
        scanner.whitespace = Whitespace1
        for scan.scan(&scanner) != '\n' {}
        scanner.whitespace = Whitespace0
    }
  }
  
  return obj, true
}