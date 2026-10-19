extends FxModule
## Постобработка всего 3D-кадра: шейдер на TextureRect, который показывает картинку
## SubViewport. Пока пусто — картинка как есть.


func setup() -> void:
	view.fx_display().material = null
