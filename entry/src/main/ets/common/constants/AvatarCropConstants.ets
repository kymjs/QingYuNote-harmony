/** 头像裁剪页完成时由 EventHub 投递；Profile 一次性监听。 */
export const AVATAR_CROP_RESULT_EVENT = 'note_avatar_crop_result'

/** EventHub 载荷（禁止匿名对象字面量，满足 arkts-no-untyped-obj-literals） */
export class AvatarCropEmitPath {
  path: string = ''

  constructor(p: string) {
    this.path = p
  }
}

export class AvatarCropEmitCancel {
  cancelled: boolean = true
}
