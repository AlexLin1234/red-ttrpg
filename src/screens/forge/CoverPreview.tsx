import { useEffect, useRef } from 'react'
import * as THREE from 'three'

/**
 * A live isometric preview of the cover being built.
 *
 * Deliberately its own tiny scene rather than a second IsoBoard: it needs one
 * box on a plinth, not a grid, picking or effects.
 */
export function CoverPreview({
  width,
  height,
  depth,
  color,
}: {
  width: number
  height: number
  depth: number
  color: number
}) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const boxRef = useRef<THREE.Mesh | null>(null)
  const disposedRef = useRef(false)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    disposedRef.current = false

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true })
    renderer.setClearColor(0x0c1117, 1)
    renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio ?? 1, 2))

    const scene = new THREE.Scene()
    const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100)
    camera.position.set(6, 6, 6)
    camera.lookAt(0, 0.5, 0)

    scene.add(new THREE.AmbientLight(0x8fa8c4, 2))
    const key = new THREE.DirectionalLight(0xd6e6f7, 2.2)
    key.position.set(5, 9, 4)
    scene.add(key)

    const plinth = new THREE.Mesh(
      new THREE.BoxGeometry(4, 0.08, 4),
      new THREE.MeshStandardMaterial({ color: 0x121a24, roughness: 0.95 }),
    )
    plinth.position.y = -0.04
    scene.add(plinth)

    const grid = new THREE.GridHelper(4, 8, 0x2d4462, 0x1b232e)
    grid.position.y = 0.005
    scene.add(grid)

    const box = new THREE.Mesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshStandardMaterial({ color: 0x3b434c, roughness: 0.65, metalness: 0.25 }),
    )
    scene.add(box)
    boxRef.current = box

    const resize = () => {
      const w = canvas.clientWidth || 1
      const h = canvas.clientHeight || 1
      const size = 3.8
      const aspect = w / h
      camera.left = -size * aspect * 0.5
      camera.right = size * aspect * 0.5
      camera.top = size * 0.5
      camera.bottom = -size * 0.5
      camera.updateProjectionMatrix()
      renderer.setSize(w, h, false)
    }
    resize()
    window.addEventListener('resize', resize)

    const loop = () => {
      if (disposedRef.current) return
      renderer.render(scene, camera)
      requestAnimationFrame(loop)
    }
    loop()

    return () => {
      disposedRef.current = true
      window.removeEventListener('resize', resize)
      boxRef.current = null
      scene.traverse((node) => {
        if (node instanceof THREE.Mesh) {
          node.geometry.dispose()
          const material = node.material
          if (Array.isArray(material)) material.forEach((entry) => entry.dispose())
          else material.dispose()
        }
      })
      renderer.dispose()
    }
  }, [])

  // Dimensions and colour change often (slider drags), so they update the
  // existing mesh instead of tearing the scene down.
  useEffect(() => {
    const box = boxRef.current
    if (!box) return
    box.scale.set(Math.max(0.1, width), Math.max(0.1, height), Math.max(0.1, depth))
    box.position.y = Math.max(0.1, height) / 2
    ;(box.material as THREE.MeshStandardMaterial).color.setHex(color)
  }, [width, height, depth, color])

  return <canvas ref={canvasRef} className="forge-preview-canvas" />
}
