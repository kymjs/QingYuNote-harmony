/** 流程图节点稳定短 ID：`node1`、`node2`…（写入 Mermaid 编码，避免 UUID 过长）。 */
export class FlowchartNodeIds {
  static next(existingIds: string[]): string {
    let max = 0
    for (let i = 0; i < existingIds.length; i++) {
      const id = existingIds[i].trim()
      if (id.length < 5) {
        continue
      }
      const lower = id.toLowerCase()
      if (!lower.startsWith('node')) {
        continue
      }
      const numStr = id.substring(4)
      let valid = true
      for (let j = 0; j < numStr.length; j++) {
        const ch = numStr.charAt(j)
        if (ch < '0' || ch > '9') {
          valid = false
          break
        }
      }
      if (!valid || numStr.length === 0) {
        continue
      }
      const n = Number.parseInt(numStr, 10)
      if (!Number.isNaN(n) && n > max) {
        max = n
      }
    }
    return `node${max + 1}`
  }

  static nextForGraph(nodeIds: string[]): string {
    return FlowchartNodeIds.next(nodeIds)
  }
}
