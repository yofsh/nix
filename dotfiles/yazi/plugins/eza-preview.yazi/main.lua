local M = {}

function M:peek(job)
	local output, err = Command("eza")
		:arg("--tree")
		:arg("--level=3")
		:arg("--color=always")
		:arg("--icons=always")
		:arg("--group-directories-first")
		:arg(tostring(job.file.url))
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:output()

	if not output or output.stdout == "" then
		ya.preview_widget(job, ui.Text("(empty)"):area(job.area))
		return
	end

	local lines = {}
	local i = 0
	for line in output.stdout:gmatch("[^\n]*") do
		i = i + 1
		if i > 1 and i > job.skip + 1 then
			table.insert(lines, ui.Line.parse(line))
		end
	end

	ya.preview_widget(job, ui.Text(lines):area(job.area))
end

function M:seek(job)
	local h = cx.active.current.hovered
	if h then
		local new_skip = math.max(0, job.skip + job.units)
		ya.emit("peek", { new_skip, only_if = tostring(h.url) })
	end
end

return M
