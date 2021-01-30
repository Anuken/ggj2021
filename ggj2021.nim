import ecs, presets/[basic, effects, content], math, random, quadtree, macros, strutils, bloom, sequtils

static: echo staticExec("faupack -p:assets-raw/sprites -o:assets/atlas")

const 
  scl = 64.0
  worldSize = 40
  tileSizePx = 32'f32
  pixelation = 2
  layerFloor = -10000000'f32
  shootPos = vec2(13, 30) / tileSizePx
  reload = 0.2
  layerBloom = 10'f32
  shadowColor = rgba(0, 0, 0, 0.2)
  layerShadow = layerFloor + 100

type
  Block = ref object of Content
    solid: bool
    patches: seq[Patch]

  Tile = object
    floor: Block
    wall: Block
  
  QuadRef = object
    entity: EntityRef
    x, y, w, h: float32

registerComponents(defaultComponentOptions):
  type
    Vel = object
      x, y: float32
    Hit = object
      w, h: float32
      x, y: float32
    Person = object
      flip: bool
      walk: float32
      shoot: float32
    DrawShadow = object
    Input = object
    Solid = object
    Damage = object
      amount: float32
    Health = object
      amount: float32
    Bullet = object
      shooter: EntityRef
      hitEffect: EffectId
    Eye = object
      time: float32
    Enemy = object

    
    Animate = object
      time: float32
    
    #bosses
    Anger = object
      time: float32
    Sadness = object
    Fear = object
      time: float32
    Joy = object
      time: float32
    
    OnHit = object
      entity: EntityRef
    OnDead = object

makeContent:
  air = Block()
  floor = Block()
  wall = Block(solid: true)
  grass = Block()

var font: Font

defineEffects:
  playerBullet:
    fillPoly(e.x, e.y, 4, 10.px, z = layerBloom, rotation = e.fin * 360.0, color = %"f3a0e1")
    fillPoly(e.x, e.y, 4, 5.px, z = layerBloom, rotation = e.fin * 360.0, color = colorWhite)
  
  joyDeath(lifetime = 1.0):
    draw("joy1".patch, e.x, e.y, color = rgba(1, 1, 1, e.fout), z = -e.y, align = daBot)
    particles(e.id, 30, e.x, e.y, 90.px * e.fin):
      fillCircle(x, y, 8.px * e.fout, color = %"fff236")
  
  death(lifetime = 1.0):
    particles(e.id, 30, e.x, e.y, 90.px * e.fin):
      fillCircle(x, y, 6.px * e.fout, color = %"ff8da3")
  
  fearDeath(lifetime = 1.0):
    draw("fear1".patch, e.x, e.y, color = rgba(1, 1, 1, e.fout), z = -e.y, align = daBot)
    particles(e.id, 30, e.x, e.y, 90.px * e.fin):
      fillCircle(x, y, 6.px * e.fout, color = %"fff236")
  
  hit(lifetime = 0.3):
    particles(e.id, 6, e.x, e.y, 70.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = %"fff236")

  fearHit(lifetime = 0.3):
    particles(e.id, 6, e.x, e.y, 70.px * e.fin):
      fillCircle(x, y, 3.px * e.fout, color = %"ff55ff")
  
  flowerBullet:
    fillCircle(e.x, e.y, 10.px, z = layerBloom, color = %"f8cc55")
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = %"fff236")
  
  shadowBullet:
    fillCircle(e.x, e.y, 10.px, z = layerBloom, color = %"ff55ff")
    fillCircle(e.x, e.y, 5.px, z = layerBloom, color = %"ffc0ff")

  shoot(lifetime = 0.2):
    poly(e.x, e.y, 10, 13.px * e.fin, stroke = 4.px * e.fout + 0.3.px, color = %"f3a0e1")
  
  ratText(lifetime = 20):
    font.draw("RAT", e.vec2, z = layerBloom, scale = 3.px)

var tiles = newSeq[Tile](worldSize * worldSize)

proc tile(x, y: int): Tile = 
  if x >= worldSize or y >= worldSize or x < 0 or y < 0: Tile(floor: blockFloor, wall: blockWall) else: tiles[x + y*worldSize]

proc solid(x, y: int): bool = tile(x, y).wall.solid

iterator eachTile*(): tuple[x, y: int, tile: Tile] =
  const pad = 2
  let 
    xrange = (fau.cam.w / 2).ceil.int + pad
    yrange = (fau.cam.h / 2).ceil.int + pad
    camx = fau.cam.pos.x.ceil.int
    camy = fau.cam.pos.y.ceil.int

  for cx in -xrange..xrange:
    for cy in -yrange..yrange:
      let 
        wcx = camx + cx
        wcy = camy + cy
      
      yield (wcx, wcy, tile(wcx, wcy))

macro shoot(t: untyped, ent: EntityRef, xp, yp, rot: float32, speed = 0.1, damage = 1'f32) =
  let effectId = ident("effectId" & t.repr.capitalizeAscii)
  result = quote do:
    let vel = vec2l(`rot`, `speed`)
    discard newEntityWith(Pos(x: `xp`, y: `yp`), Timed(lifetime: 4), Effect(id: `effectId`, rotation: `rot`), Bullet(shooter: `ent`, hitEffect: effectIdHit), Hit(w: 0.2, h: 0.2), Vel(x: vel.x, y: vel.y), Damage(amount: `damage`))

template rect(pos: untyped, hit: untyped): Rect = rectCenter(pos.x + hit.x, pos.y + hit.y, hit.w, hit.h)

macro whenComp(entity: EntityRef, t: typedesc, body: untyped) =
  let varName = t.repr.toLowerAscii.ident
  result = quote do:
    if `entity`.alive and `entity`.hasComponent `t`:
      let `varName` {.inject.} = `entity`.fetchComponent `t`
      `body`

sys("init", [Main]):

  init:
    fau.pixelScl = 1.0 / tileSizePx

    initContent()
    #player
    discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2), Person(), Vel(), Hit(w: 0.6, h: 0.4), Solid(), Input(), Health(amount: 5))

    #anger
    #discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2 + 3), Anger(), Vel(), Hit(w: 3, h: 8, y: 4), Solid(), Health(amount: 5), Animate())

    #joy
    #discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2 + 3), Joy(), Vel(), Hit(w: 2, h: 6, y: 3), Solid(), Health(amount: 50), Animate())

    #fear
    discard newEntityWith(Pos(x: worldSize/2, y: worldSize/2 + 3), Fear(), Vel(), Hit(w: 2, h: 5.2, y: 3.5), Solid(), Health(amount: 50), Animate(), Enemy())


    #effectRatText(worldSize/2, worldSize/2 + 4)

    for tile in tiles.mitems:
      tile.floor = blockGrass
      tile.wall = blockAir

      #if rand(10) < 1: tile.wall = blockWall
  
sys("controlled", [Person, Input, Pos, Vel]):
  all:
    let v = vec2(axis(keyA, keyD), axis(KeyCode.keyS, keyW)).lim(1) * 6 * fau.delta
    item.vel.x += v.x
    item.vel.y += v.y
    item.person.shoot -= fau.delta

    if keyMouseLeft.down:
      if item.person.shoot <= 0:
        let offset = shootPos * vec2(-item.person.flip.sign, 1) + item.pos.vec2
        let ang = offset.angle(mouseWorld())
        shoot(playerBullet, item.entity, offset.x, offset.y, rot = ang, speed = 0.3)
        item.person.shoot = reload
        effectShoot(offset.x, offset.y)
        item.person.flip = ang >= 90.rad and ang < 270.rad

sys("animatePerson", [Vel, Person]):
  all:
    if abs(item.vel.x) >= 0.001:
      item.person.flip = item.vel.x < 0
    
    if len(item.vel.x, item.vel.y) >= 0.01:
      item.person.walk += fau.delta
    else:
      item.person.walk = 0

sys("quadtree", [Pos, Vel, Hit]):
  vars:
    tree: Quadtree[QuadRef]
  init:
    sys.tree = newQuadtree[QuadRef](rect(-0.5, -0.5, worldSize + 1, worldSize + 1))
  start:
    sys.tree.clear()
  all:
    sys.tree.insert(QuadRef(entity: item.entity, x: item.pos.x - item.hit.w/2.0 + item.hit.x, y: item.pos.y - item.hit.h/2.0 + item.hit.y, w: item.hit.w, h: item.hit.h))

#TODO only 1 collision per frame
sys("collide", [Pos, Vel, Bullet, Hit]):
  vars:
    output: seq[QuadRef]
  all:
    sys.output.setLen(0)
    let r = rect(item.pos, item.hit)
    sysQuadtree.tree.intersect(r, sys.output)
    for elem in sys.output:
      if elem.entity != item.bullet.shooter and elem.entity != item.entity and elem.entity.alive and item.bullet.shooter.alive and not(elem.entity.hasComponent(Enemy) and item.bullet.shooter.hasComponent(Enemy)):
        let 
          hitter = item.entity
          target = elem.entity
        
        whenComp(hitter, Damage):
          whenComp(target, Health):
            health.amount -= damage.amount

            let pos = hitter.fetchComponent Pos
            if target.hasComponent Fear: effectFearHit(pos.x, pos.y)
            elif target.hasComponent Joy: effectHit(pos.x, pos.y)
            elif target.hasComponent Person: effectHit(pos.x, pos.y)
            else: effectHit(pos.x, pos.y)

            if health.amount <= 0:
              let tpos = target.fetchComponent Pos

              if target.hasComponent Joy: effectJoyDeath(tpos.x, tpos.y)
              if target.hasComponent Fear: effectFearDeath(tpos.x, tpos.y)
              if target.hasComponent Person: effectDeath(tpos.x, tpos.y)
              else: effectDeath(tpos.x, tpos.y)

              target.delete()
            hitter.delete()
            break

sys("bulletMove", [Pos, Vel, Bullet]):
  all:
    item.pos.x += item.vel.x
    item.pos.y += item.vel.y

sys("bulletHitWall", [Pos, Vel, Bullet, Hit]):
  all:
    if collidesTiles(rect(item.pos, item.hit), proc(x, y: int): bool = solid(x, y)):
      item.entity.delete()

sys("moveSolid", [Pos, Vel, Solid, Hit]):
  all:
    let delta = moveDelta(rect(item.pos, item.hit), item.vel.x, item.vel.y, proc(x, y: int): bool = solid(x, y))
    item.pos.x += delta.x
    item.pos.y += delta.y
    item.vel.x = 0
    item.vel.y = 0

sys("animation", [Animate]):
  all:
    item.animate.time += fau.delta

sys("eye", [Pos, Eye, Solid, Hit, Vel, Animate]):
  all:
    let move = vec2(sin(item.pos.y + item.pos.x / 10.0, 2.2, 2.0), sin(item.pos.x + item.pos.y / 30.0, 3.0, 3.0)).nor * 0.1
    item.vel.x += move.x
    item.vel.y += move.y

    item.eye.time += fau.delta
    if item.eye.time > 2.0:
      circle(4):
        shoot(shadowBullet, item.entity, item.pos.x, item.pos.y, rot = angle)
      
      item.eye.time = 0

sys("joyBoss", [Pos, Joy, Animate]):
  all:
    item.joy.time += fau.delta
    if item.joy.time > 0.3:
      circle(10):
        shoot(flowerBullet, item.entity, item.pos.x, item.pos.y + 166.px, rot = angle + item.animate.time / 3.0)
      
      item.joy.time = 0

sys("fearBoss", [Pos, Fear, Animate]):
  all:
    item.fear.time += fau.delta
    if item.fear.time > 0.25:
      circle(12):
        shoot(shadowBullet, item.entity, item.pos.x + 4.px, item.pos.y + 139.px, rot = angle + item.animate.time / 3.0)
      
      item.fear.time = 0

      if chance(0.1):
        discard newEntityWith(Pos(x: item.pos.x + rand(-1..1), y: item.pos.y + 1 + rand(-1..1)), Vel(), Hit(w: 16.px, h: 16.px, y: 3.px), Solid(), Health(amount: 1), Animate(), Eye(), Enemy())


makeTimedSystem()

sys("followCam", [Pos, Input]):
  all:
    fau.cam.pos = vec2(item.pos.x, item.pos.y + 32.px)
    fau.cam.pos += vec2((fau.widthf mod scl) / scl, (fau.heightf mod scl) / scl) * fau.pixelScl

sys("draw", [Main]):
  vars:
    buffer: Framebuffer
    shadows: Framebuffer
    #bloom: Bloom
  init:
    sys.buffer = newFramebuffer()
    sys.shadows = newFramebuffer()
    font = loadFont("font.ttf")
    #sys.bloom = newBloom()

    #load all block textures before rendering
    for b in blockList:
      var maxFound = 0
      for i in 1..12:
        if not fau.atlas.patches.hasKey(b.name & $i): break
        maxFound = i
      
      if maxFound == 0:
        if fau.atlas.patches.hasKey(b.name):
          b.patches = @[b.name.patch]
      else:
        b.patches = (1..maxFound).toSeq().mapIt((b.name & $it).patch)
    
  start:
    if keyEscape.tapped: quitApp()
    
    fau.cam.resize(fau.widthf / scl, fau.heightf / scl)
    fau.cam.use()

    sys.buffer.resize(fau.width div pixelation, fau.height div pixelation)
    sys.shadows.resize(sys.buffer.width, sys.buffer.height)
    let 
      buf = sys.buffer
      shadows = sys.shadows
      #bloom = sys.bloom

    buf.push()

    draw(100, proc() =
      buf.pop()
      buf.blitQuad()
    )

    drawLayer(layerShadow, proc() = shadows.push(colorClear), proc() =
      shadows.pop()
      shadows.blit(color = shadowColor)
    )

    #drawLayer(layerBloom, proc() = bloom.capture(), proc() = bloom.render())

    for x, y, t in eachTile():
      let r = hashInt(x + y * worldSize)
      draw(t.floor.patches[r mod t.floor.patches.len], x, y, layerFloor)
       
      if t.wall.id != 0:
        let reg = t.wall.name.patch
        draw(reg, x, y - 0.5, -(y - 0.5), align = daBot)

proc frame(pre: string, time, speed: float32): string = pre & $([1, 2, 3, 2][((time * speed) mod 4).int])

sys("drawEye", [Eye, Pos, Animate]):
  all:
    draw(frame("eye", item.animate.time, 4).patch, item.pos.x, item.pos.y + 5.px, align = daBot, z = -item.pos.y)

sys("drawFear", [Fear, Pos, Animate]):
  all:
    let si = item.animate.time.sin(2, 15.px).abs
    draw(frame("fear", item.animate.time, 4).patch, item.pos.x, item.pos.y - 6.px, align = daBot, z = -item.pos.y)

sys("drawJoy", [Joy, Pos, Animate]):
  all:
    draw(frame("joy", item.animate.time, 5).patch, item.pos.x, item.pos.y - 6.px, align = daBot, z = -item.pos.y)

sys("drawShadow", [Pos, Solid, Hit]):
  all:
    draw("circle".patch, item.pos.x, item.pos.y - 3.px, z = layerShadow, width = item.hit.w * 1.8'f32, height = 10.px + item.hit.w / 6.0)

sys("drawPerson", [Person, Pos]):
  vars:
    shader: Shader
  init:
    sys.shader = newShader(defaultBatchVert, 
    """
    varying lowp vec4 v_color;
    varying lowp vec4 v_mixcolor;
    varying vec2 v_texc;
    uniform sampler2D u_texture;
    void main(){
      vec4 c = texture2D(u_texture, v_texc);
      gl_FragColor = v_color * mix(c, vec4(v_mixcolor.rgb, c.a), v_mixcolor.a);
    }
    """)
  all:
    
    var p = if keyMouseLeft.down: "player_attack_1".patch else: "player".patch
    if item.person.walk > 0:
      p = frame((if keyMouseLeft.down: "player_attack_" else: "player_walk_"), item.person.walk, 6).patch
    let
      x = item.pos.x
      y = item.pos.y - 4.px
      width = p.widthf.px * -item.person.flip.sign
      shader = sys.shader
    draw(-item.pos.y, proc() =
      withShader(shader):
        draw(p, x, y, align = daBot, width = width)
    )
    

makeEffectsSystem()

launchFau("ggj2021")
