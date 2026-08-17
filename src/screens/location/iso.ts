/**
 * The isometric board.
 *
 * A thin wrapper over three.js that knows about grid cells rather than world
 * units, so React only ever deals in `{x, z, layer}`. It owns picking, the
 * line-of-sight raycast that drives the cover prompt, and the shot and blast
 * effects.
 */

import * as THREE from 'three'

import type { BoardProp, BoardUnit, CoverDefinition, GameLocation } from '../../core/campaign/schema'

export interface Cell {
  x: number
  z: number
  layer: number
}

export type PickTarget =
  | { kind: 'unit'; id: string; cell: Cell }
  | { kind: 'prop'; id: string; cell: Cell }
  | { kind: 'ground'; cell: Cell }

export interface UnitVisual {
  id: string
  characterId: string
  name: string
  side: 'party' | 'hostile' | 'neutral'
  hpRatio: number
  down: boolean
}

export interface CoverHit {
  propId: string
  coverId: string
  /** Metres from the shooter to the blocking prop. */
  distanceM: number
  /** How much of the target the prop occludes, 0-1, sampled over its silhouette. */
  occlusion: number
}

const LAYER_HEIGHT = 1.2
const SIDE_COLORS: Record<UnitVisual['side'], number> = {
  party: 0x93bce2,
  hostile: 0xbb5451,
  neutral: 0xd9b45c,
}

export class IsoBoard {
  private renderer: THREE.WebGLRenderer
  private scene = new THREE.Scene()
  private camera: THREE.OrthographicCamera
  private raycaster = new THREE.Raycaster()
  private pointer = new THREE.Vector2()

  private groundGroup = new THREE.Group()
  private propGroup = new THREE.Group()
  private unitGroup = new THREE.Group()
  private effectGroup = new THREE.Group()
  private overlayGroup = new THREE.Group()

  private propMeshes = new Map<string, THREE.Mesh>()
  private unitMeshes = new Map<string, THREE.Object3D>()
  private selectionRing: THREE.Mesh
  private hoverTile: THREE.Mesh

  private location: GameLocation | null = null
  private covers = new Map<string, CoverDefinition>()
  private frame = 0
  private disposed = false
  private zoom = 26
  private effects: { object: THREE.Object3D; born: number; life: number; update: (t: number) => void }[] = []

  constructor(private canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false })
    this.renderer.setClearColor(0x0c1117, 1)
    this.renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio ?? 1, 2))

    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 400)
    // A true isometric view: equal angles down all three axes.
    this.camera.position.set(60, 60, 60)
    this.camera.lookAt(0, 0, 0)

    this.scene.add(this.groundGroup, this.propGroup, this.unitGroup, this.effectGroup, this.overlayGroup)
    this.scene.add(new THREE.AmbientLight(0x8fa8c4, 1.9))

    const key = new THREE.DirectionalLight(0xd6e6f7, 2.1)
    key.position.set(30, 60, 20)
    this.scene.add(key)
    const fill = new THREE.DirectionalLight(0x6f9bc4, 0.8)
    fill.position.set(-25, 30, 35)
    this.scene.add(fill)
    const rim = new THREE.DirectionalLight(0xbb5451, 0.7)
    rim.position.set(-40, 20, -30)
    this.scene.add(rim)

    this.selectionRing = new THREE.Mesh(
      new THREE.RingGeometry(0.62, 0.78, 32),
      new THREE.MeshBasicMaterial({ color: 0x93bce2, side: THREE.DoubleSide, transparent: true }),
    )
    this.selectionRing.rotation.x = -Math.PI / 2
    this.selectionRing.visible = false
    this.overlayGroup.add(this.selectionRing)

    this.hoverTile = new THREE.Mesh(
      new THREE.PlaneGeometry(1, 1),
      new THREE.MeshBasicMaterial({ color: 0x93bce2, transparent: true, opacity: 0.16 }),
    )
    this.hoverTile.rotation.x = -Math.PI / 2
    this.hoverTile.visible = false
    this.overlayGroup.add(this.hoverTile)

    this.resize()
    this.tick()
  }

  // -- geometry helpers ------------------------------------------------------

  private half(): { x: number; z: number } {
    return {
      x: (this.location?.gridWidth ?? 20) / 2 - 0.5,
      z: (this.location?.gridHeight ?? 20) / 2 - 0.5,
    }
  }

  /** Grid cell to world position, centred on the cell. */
  worldOf(cell: Cell): THREE.Vector3 {
    const half = this.half()
    return new THREE.Vector3(cell.x - half.x, cell.layer * LAYER_HEIGHT, cell.z - half.z)
  }

  private cellOf(point: THREE.Vector3, layer = 0): Cell {
    const half = this.half()
    return {
      x: Math.round(point.x + half.x),
      z: Math.round(point.z + half.z),
      layer,
    }
  }

  /** Distance between two cells in metres, using the location's tile scale. */
  distanceM(a: Cell, b: Cell): number {
    const tile = this.location?.tileMetres ?? 2
    return Math.hypot(a.x - b.x, a.z - b.z) * tile
  }

  // -- scene building --------------------------------------------------------

  setLocation(location: GameLocation, covers: readonly CoverDefinition[]): void {
    this.location = location
    this.covers = new Map(covers.map((cover) => [cover.id, cover]))
    this.rebuildGround()
    this.rebuildProps()
    this.zoom = Math.max(location.gridWidth, location.gridHeight) * 1.15
    this.resize()
  }

  private clear(group: THREE.Group): void {
    for (const child of [...group.children]) {
      group.remove(child)
      child.traverse((node) => {
        if (node instanceof THREE.Mesh) {
          node.geometry.dispose()
          const material = node.material
          if (Array.isArray(material)) material.forEach((entry) => entry.dispose())
          else material.dispose()
        }
      })
    }
  }

  private rebuildGround(): void {
    this.clear(this.groundGroup)
    const location = this.location
    if (!location) return

    // One instanced mesh for the deck: a 20 x 20 board is 400 draw calls
    // otherwise, and boards get bigger than that.
    const geometry = new THREE.BoxGeometry(0.96, 0.12, 0.96)
    // The material stays white: instanceColor multiplies into it, so any tint
    // here would be applied twice and crush the deck to black.
    const material = new THREE.MeshStandardMaterial({
      color: 0xffffff,
      roughness: 0.82,
      metalness: 0.12,
    })
    const mesh = new THREE.InstancedMesh(geometry, material, location.tiles.length)
    const matrix = new THREE.Matrix4()
    const color = new THREE.Color()
    location.tiles.forEach((tile, index) => {
      const position = this.worldOf(tile)
      matrix.makeTranslation(position.x, position.y - 0.06, position.z)
      mesh.setMatrixAt(index, matrix)
      // Elevation shading: higher layers read lighter.
      const lift = 1 + tile.layer * 0.4
      // A faint checker keeps the grid legible when the helper lines are off.
      const base = (tile.x + tile.z) % 2 === 0 ? 0x2b3a4d : 0x25323f
      color.setHex(base).multiplyScalar(lift)
      mesh.setColorAt(index, color)
    })
    mesh.instanceMatrix.needsUpdate = true
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true
    mesh.name = 'deck'
    this.groundGroup.add(mesh)

    const grid = new THREE.GridHelper(
      Math.max(location.gridWidth, location.gridHeight),
      Math.max(location.gridWidth, location.gridHeight),
      0x243044,
      0x1b232e,
    )
    grid.position.y = 0.005
    this.groundGroup.add(grid)
  }

  private rebuildProps(): void {
    this.clear(this.propGroup)
    this.propMeshes.clear()
    const location = this.location
    if (!location) return

    for (const prop of location.props) {
      const cover = this.covers.get(prop.coverId)
      if (!cover) continue
      const tile = location.tileMetres
      const mesh = new THREE.Mesh(
        new THREE.BoxGeometry(cover.width / tile, cover.height / tile, cover.depth / tile),
        new THREE.MeshStandardMaterial({
          color: materialColor(cover.material),
          roughness: 0.7,
          metalness: 0.25,
        }),
      )
      const position = this.worldOf(prop)
      mesh.position.set(position.x, position.y + cover.height / tile / 2, position.z)
      mesh.rotation.y = (prop.rotation * Math.PI) / 180
      mesh.userData = { kind: 'prop', id: prop.id, coverId: cover.id, cell: cellOfProp(prop) }
      this.propGroup.add(mesh)
      this.propMeshes.set(prop.id, mesh)
    }
  }

  setUnits(units: readonly BoardUnit[], visuals: Map<string, UnitVisual>): void {
    this.clear(this.unitGroup)
    this.unitMeshes.clear()

    for (const unit of units) {
      const visual = visuals.get(unit.characterId)
      if (!visual) continue
      const group = new THREE.Group()
      const position = this.worldOf(unit)
      group.position.set(position.x, position.y, position.z)

      const body = new THREE.Mesh(
        new THREE.CylinderGeometry(0.36, 0.42, visual.down ? 0.24 : 1.05, 18),
        new THREE.MeshStandardMaterial({
          color: SIDE_COLORS[visual.side],
          emissive: SIDE_COLORS[visual.side],
          emissiveIntensity: visual.down ? 0.1 : 0.35,
          roughness: 0.5,
        }),
      )
      body.position.y = visual.down ? 0.12 : 0.55
      body.userData = { kind: 'unit', id: unit.id, characterId: unit.characterId, cell: cellOfUnit(unit) }
      group.add(body)

      // A base disc that reads as the unit's footprint on the grid.
      const base = new THREE.Mesh(
        new THREE.CircleGeometry(0.44, 24),
        new THREE.MeshBasicMaterial({
          color: SIDE_COLORS[visual.side],
          transparent: true,
          opacity: 0.28,
        }),
      )
      base.rotation.x = -Math.PI / 2
      base.position.y = 0.02
      group.add(base)

      // A short health pip floating over the token.
      const pip = new THREE.Mesh(
        new THREE.PlaneGeometry(Math.max(0.06, 0.8 * visual.hpRatio), 0.07),
        new THREE.MeshBasicMaterial({
          color: visual.hpRatio > 0.5 ? 0x6fbf8b : visual.hpRatio > 0.25 ? 0xd9b45c : 0xbb5451,
        }),
      )
      pip.position.set(0, 1.35, 0)
      pip.userData.billboard = true
      group.add(pip)

      group.userData = { kind: 'unit', id: unit.id, characterId: unit.characterId }
      this.unitGroup.add(group)
      this.unitMeshes.set(unit.id, group)
    }
  }

  setSelection(unitId: string | null): void {
    const target = unitId ? this.unitMeshes.get(unitId) : null
    if (!target) {
      this.selectionRing.visible = false
      return
    }
    this.selectionRing.visible = true
    this.selectionRing.position.set(target.position.x, target.position.y + 0.04, target.position.z)
  }

  setHoverCell(cell: Cell | null): void {
    if (!cell) {
      this.hoverTile.visible = false
      return
    }
    const position = this.worldOf(cell)
    this.hoverTile.visible = true
    this.hoverTile.position.set(position.x, position.y + 0.07, position.z)
  }

  // -- interaction -----------------------------------------------------------

  private setPointer(event: { clientX: number; clientY: number }): void {
    const rect = this.canvas.getBoundingClientRect()
    this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1
    this.pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1
    this.raycaster.setFromCamera(this.pointer, this.camera)
  }

  pick(event: { clientX: number; clientY: number }): PickTarget | null {
    this.setPointer(event)

    const unitHits = this.raycaster.intersectObjects(this.unitGroup.children, true)
    const unitHit = unitHits.find((hit) => hit.object.userData?.kind === 'unit')
    if (unitHit) {
      const data = unitHit.object.userData as { id: string; cell: Cell }
      return { kind: 'unit', id: data.id, cell: data.cell }
    }

    const propHits = this.raycaster.intersectObjects(this.propGroup.children, false)
    const propHit = propHits[0]
    if (propHit) {
      const data = propHit.object.userData as { id: string; cell: Cell }
      return { kind: 'prop', id: data.id, cell: data.cell }
    }

    const groundHits = this.raycaster.intersectObjects(this.groundGroup.children, false)
    const groundHit = groundHits.find((hit) => hit.object.name === 'deck')
    if (groundHit) return { kind: 'ground', cell: this.cellOf(groundHit.point) }

    // Fall back to the y = 0 plane so drops past the deck edge still land.
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0)
    const point = new THREE.Vector3()
    if (this.raycaster.ray.intersectPlane(plane, point)) {
      return { kind: 'ground', cell: this.cellOf(point) }
    }
    return null
  }

  /**
   * Is anything between these two cells?
   *
   * Samples several rays across the target's silhouette rather than one down
   * the centre, so a barrier that clips the edge of a target reports partial
   * occlusion instead of none.
   */
  coverBetween(from: Cell, to: Cell): CoverHit | null {
    const origin = this.worldOf(from).setY(this.worldOf(from).y + 0.9)
    const target = this.worldOf(to).setY(this.worldOf(to).y + 0.9)
    const props = [...this.propGroup.children]
    if (props.length === 0) return null

    const axis = new THREE.Vector3().subVectors(target, origin)
    const side = new THREE.Vector3(-axis.z, 0, axis.x).normalize().multiplyScalar(0.34)
    const offsets = [-1, -0.5, 0, 0.5, 1]

    let blocked = 0
    let nearest: { propId: string; coverId: string; distance: number } | null = null

    for (const factor of offsets) {
      const shifted = target.clone().addScaledVector(side, factor)
      const direction = new THREE.Vector3().subVectors(shifted, origin)
      const span = direction.length()
      direction.normalize()
      const caster = new THREE.Raycaster(origin, direction, 0.1, span - 0.35)
      const hit = caster.intersectObjects(props, false)[0]
      if (!hit) continue
      blocked += 1
      const data = hit.object.userData as { id: string; coverId: string }
      if (!nearest || hit.distance < nearest.distance) {
        nearest = { propId: data.id, coverId: data.coverId, distance: hit.distance }
      }
    }

    if (!nearest) return null
    const tile = this.location?.tileMetres ?? 2
    return {
      propId: nearest.propId,
      coverId: nearest.coverId,
      distanceM: Math.round(nearest.distance * tile * 10) / 10,
      occlusion: blocked / offsets.length,
    }
  }

  // -- effects ---------------------------------------------------------------

  playShot(from: Cell, to: Cell, hit: boolean): void {
    const start = this.worldOf(from).setY(this.worldOf(from).y + 0.85)
    const end = this.worldOf(to).setY(this.worldOf(to).y + 0.85)
    const geometry = new THREE.BufferGeometry().setFromPoints([start, end])
    const material = new THREE.LineBasicMaterial({
      color: hit ? 0xffd88a : 0x6b7d94,
      transparent: true,
    })
    const line = new THREE.Line(geometry, material)
    this.effectGroup.add(line)
    this.effects.push({
      object: line,
      born: this.frame,
      life: 26,
      update: (t) => {
        material.opacity = 1 - t
      },
    })

    if (hit) this.playImpact(end)
  }

  private playImpact(position: THREE.Vector3): void {
    const material = new THREE.MeshBasicMaterial({
      color: 0xffb066,
      transparent: true,
      side: THREE.DoubleSide,
    })
    const flash = new THREE.Mesh(new THREE.SphereGeometry(0.22, 12, 10), material)
    flash.position.copy(position)
    this.effectGroup.add(flash)
    this.effects.push({
      object: flash,
      born: this.frame,
      life: 22,
      update: (t) => {
        flash.scale.setScalar(1 + t * 2.2)
        material.opacity = 1 - t
      },
    })
  }

  /** An expanding shell plus a ground ring, sized in metres. */
  playBlast(centre: Cell, radiusM: number): void {
    const tile = this.location?.tileMetres ?? 2
    const radius = radiusM / tile
    const position = this.worldOf(centre)

    const shellMaterial = new THREE.MeshBasicMaterial({
      color: 0xff9a4d,
      transparent: true,
      opacity: 0.5,
    })
    const shell = new THREE.Mesh(new THREE.SphereGeometry(radius, 20, 16), shellMaterial)
    shell.position.set(position.x, position.y + 0.6, position.z)
    this.effectGroup.add(shell)
    this.effects.push({
      object: shell,
      born: this.frame,
      life: 40,
      update: (t) => {
        shell.scale.setScalar(0.25 + t * 0.95)
        shellMaterial.opacity = 0.55 * (1 - t)
      },
    })

    const ringMaterial = new THREE.MeshBasicMaterial({
      color: 0xbb5451,
      transparent: true,
      side: THREE.DoubleSide,
    })
    const ring = new THREE.Mesh(new THREE.RingGeometry(radius * 0.94, radius, 48), ringMaterial)
    ring.rotation.x = -Math.PI / 2
    ring.position.set(position.x, position.y + 0.08, position.z)
    this.effectGroup.add(ring)
    this.effects.push({
      object: ring,
      born: this.frame,
      life: 48,
      update: (t) => {
        ringMaterial.opacity = 0.9 * (1 - t)
      },
    })
  }

  /** A persistent ring showing a pending blast radius while the GM aims. */
  showBlastPreview(centre: Cell | null, radiusM: number): void {
    const existing = this.overlayGroup.getObjectByName('blast-preview')
    if (existing) {
      this.overlayGroup.remove(existing)
      if (existing instanceof THREE.Mesh) {
        existing.geometry.dispose()
        ;(existing.material as THREE.Material).dispose()
      }
    }
    if (!centre) return
    const tile = this.location?.tileMetres ?? 2
    const radius = radiusM / tile
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(radius * 0.93, radius, 48),
      new THREE.MeshBasicMaterial({
        color: 0xbb5451,
        transparent: true,
        opacity: 0.75,
        side: THREE.DoubleSide,
      }),
    )
    ring.name = 'blast-preview'
    ring.rotation.x = -Math.PI / 2
    const position = this.worldOf(centre)
    ring.position.set(position.x, position.y + 0.09, position.z)
    this.overlayGroup.add(ring)
  }

  // -- loop ------------------------------------------------------------------

  resize(): void {
    const width = this.canvas.clientWidth || 1
    const height = this.canvas.clientHeight || 1
    const aspect = width / height
    const size = this.zoom
    this.camera.left = -size * aspect * 0.5
    this.camera.right = size * aspect * 0.5
    this.camera.top = size * 0.5
    this.camera.bottom = -size * 0.5
    this.camera.updateProjectionMatrix()
    this.renderer.setSize(width, height, false)
  }

  setZoom(delta: number): void {
    this.zoom = Math.min(60, Math.max(10, this.zoom + delta))
    this.resize()
  }

  private tick = (): void => {
    if (this.disposed) return
    this.frame += 1

    for (let index = this.effects.length - 1; index >= 0; index -= 1) {
      const effect = this.effects[index]!
      const age = (this.frame - effect.born) / effect.life
      if (age >= 1) {
        this.effectGroup.remove(effect.object)
        this.effects.splice(index, 1)
        continue
      }
      effect.update(age)
    }

    // Health pips face the camera.
    for (const unit of this.unitMeshes.values()) {
      for (const child of unit.children) {
        if (child.userData.billboard) child.quaternion.copy(this.camera.quaternion)
      }
    }

    this.renderer.render(this.scene, this.camera)
    requestAnimationFrame(this.tick)
  }

  dispose(): void {
    this.disposed = true
    this.clear(this.groundGroup)
    this.clear(this.propGroup)
    this.clear(this.unitGroup)
    this.clear(this.effectGroup)
    this.renderer.dispose()
  }
}

function cellOfProp(prop: BoardProp): Cell {
  return { x: prop.x, z: prop.z, layer: prop.layer }
}

function cellOfUnit(unit: BoardUnit): Cell {
  return { x: unit.x, z: unit.z, layer: unit.layer }
}

function materialColor(material: string): number {
  switch (material) {
    case 'Concrete':
      return 0x3b434c
    case 'Steel Plate':
      return 0x4a5666
    case 'Glass':
      return 0x2f5566
    case 'Sheet Metal':
      return 0x5a5f66
    case 'Wood Crate':
      return 0x6a4a26
    case 'Vehicle Hulk':
      return 0x63343a
    default:
      return 0x39414b
  }
}
