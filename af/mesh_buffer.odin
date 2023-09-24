package af

import "core:c"

MeshBuffer :: struct {
	mesh:                          ^Mesh,
	vertices_count, indices_count: c.uint,

	// TODO: currently just disables drawing when flushing, but eventually I want it to resize the backeng arrays like a list,
	// so that we can build meshes like how you would build a string
	is_builder:                    bool,
}

NLineStrip :: struct {
	v1, v2:             Vertex,
	v1_index, v2_index: c.uint,
	started:            bool,
	output:             ^MeshBuffer,
}

NGon :: struct {
	v1, v2:             Vertex,
	v1_index, v2_index: c.uint,
	count:              c.uint,
	output:             ^MeshBuffer,
}


MeshBuffer_Make :: proc(vert_capacity, indices_capacity: c.uint) -> ^MeshBuffer {
	DebugLog("making mesh")
	backing_mesh := Mesh_Make(vert_capacity, indices_capacity)
	DebugLog("mesh made")
	Mesh_Upload(backing_mesh, true)
	DebugLog("uploaded")

	buffer := new(MeshBuffer)
	buffer.mesh = backing_mesh

	return buffer
}

MeshBuffer_Free :: proc(output: ^MeshBuffer) {
	Mesh_Free(output.mesh)

	free(output)
}

MeshBuffer_Flush :: proc(output: ^MeshBuffer) {
	if output.vertices_count == 0 && output.indices_count == 0 {
		return
	}

	if !output.is_builder {
		Mesh_Reupload(output.mesh, output.vertices_count, output.indices_count)
		Mesh_Draw(output.mesh, output.indices_count)
	}
	
	output.vertices_count = 0
	output.indices_count = 0
}

MeshBuffer_AddVertex :: proc(output: ^MeshBuffer, vertex: Vertex) -> c.uint {
	count := output.vertices_count
	assert(count + 1 <= output.mesh.vertices_length)

	output.mesh.vertices[count] = vertex
	output.vertices_count += 1
	return count
}

MeshBuffer_AddTriangle :: proc(output: ^MeshBuffer, v1, v2, v3: c.uint) {
	count := output.indices_count
	assert(count + 3 <= output.mesh.indices_length)

	output.mesh.indices[count + 0] = v1
	output.mesh.indices[count + 1] = v2
	output.mesh.indices[count + 2] = v3
	output.indices_count += 3
}

MeshBuffer_AddQuad :: proc(output: ^MeshBuffer, v1, v2, v3, v4: c.uint) {
	MeshBuffer_AddTriangle(output, v1, v2, v3)
	MeshBuffer_AddTriangle(output, v3, v4, v1)
}

MeshBuffer_HasEnoughSpace :: proc(
	output: ^MeshBuffer,
	incoming_verts, incoming_indices: c.uint,
) -> bool {
	return(
		(output.indices_count + incoming_indices < output.mesh.indices_length) &&
		(output.vertices_count + incoming_verts < output.mesh.vertices_length) \
	)
}

MeshBuffer_FlushIfNotEnoughSpace :: proc(
	output: ^MeshBuffer,
	incoming_verts, incoming_indices: c.uint,
) -> bool {
	if (!MeshBuffer_HasEnoughSpace(output, incoming_verts, incoming_indices)) {
		MeshBuffer_Flush(output)
		return true
	}

	return false
}

NLineStrip_Begin :: proc(output: ^MeshBuffer) -> NLineStrip {
	state: NLineStrip
	state.started = false
	state.output = output
	return state
}

NLineStrip_Extend :: proc(line: ^NLineStrip, v1, v2: Vertex) {
	output: ^MeshBuffer = line.output
	if (!line.started) {
		MeshBuffer_FlushIfNotEnoughSpace(output, 4, 6)

		line.v1 = v1
		line.v2 = v2
		line.v1_index = MeshBuffer_AddVertex(output, v1)
		line.v2_index = MeshBuffer_AddVertex(output, v2)
		line.started = true
		return
	}

	if (MeshBuffer_FlushIfNotEnoughSpace(output, 2, 6)) {
		// v1 and v2 just got flushed, so we need to re-add them
		line.v1_index = MeshBuffer_AddVertex(output, line.v1)
		line.v2_index = MeshBuffer_AddVertex(output, line.v2)
	}

	next_last_1_index := MeshBuffer_AddVertex(output, v1)
	next_last_2_index := MeshBuffer_AddVertex(output, v2)

	MeshBuffer_AddTriangle(output, line.v1_index, line.v2_index, next_last_2_index)
	MeshBuffer_AddTriangle(output, next_last_2_index, next_last_1_index, line.v1_index)

	line.v1 = v1
	line.v2 = v2
	line.v1_index = next_last_1_index
	line.v2_index = next_last_2_index
}


NGon_Begin :: proc(output: ^MeshBuffer) -> NGon {
	ngon: NGon
	ngon.count = 0
	ngon.output = output
	return ngon
}

NGon_Extend :: proc(ngon: ^NGon, v: Vertex) {
	output: ^MeshBuffer = ngon.output

	// we need at least 2 vertices to start creating triangles with NGonContinue.
	if (ngon.count == 0) {
		MeshBuffer_FlushIfNotEnoughSpace(output, 3, 3)

		ngon.v1_index = MeshBuffer_AddVertex(output, v)
		ngon.v1 = v
		ngon.count += 1
		return
	}

	if (ngon.count == 1) {
		MeshBuffer_FlushIfNotEnoughSpace(output, 2, 3)

		ngon.v2_index = MeshBuffer_AddVertex(output, v)
		ngon.v2 = v
		ngon.count += 1
		return
	}

	if (MeshBuffer_FlushIfNotEnoughSpace(output, 1, 3)) {
		// v1 and v2 just got flushed, so we need to re-add them
		ngon.v1_index = MeshBuffer_AddVertex(output, ngon.v1)
		ngon.v2_index = MeshBuffer_AddVertex(output, ngon.v2)
	}

	v3 := MeshBuffer_AddVertex(output, v)
	MeshBuffer_AddTriangle(output, ngon.v1_index, ngon.v2_index, v3)

	ngon.v2_index = v3
	ngon.v2 = v
	ngon.count += 1
}
