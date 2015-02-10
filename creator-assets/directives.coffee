Adventure = angular.module "AdventureCreator"

Adventure.directive "toast", ($timeout) ->
	restrict: "E",
	link: ($scope, $element, $attrs) ->

		$scope.toastMessage = ""
		$scope.showToast = false

		# Displays a toast with the given message.
		# The autoCancel flag determines if the toast should automatically expire after 5 seconds
		# If false, the toast will remain until clicked or disabled manually in code
		$scope.toast = (message, autoCancel = true) ->
			$scope.toastMessage = message
			$scope.showToast = true

			if autoCancel
				$timeout (() ->
					$scope.hideToast()
				), 5000

		$scope.hideToast = () ->
			$scope.showToast = false


Adventure.directive 'enterSubmit', ($compile) ->
	($scope, $element, $attrs) ->
		$element.bind "keydown keypress", (event) ->
			if event.which is 13
				$scope.$apply ->
					$scope.$eval $attrs.enterSubmit

				event.preventDefault()

Adventure.directive "treeVisualization", (treeSrv) ->
	restrict: "E",
	scope: {
		data: "=", # binds treeData in a way that's accessible to the directive
		onClick: "&" # binds a listener so the controller can access the directive's click data
	},
	link: ($scope, $element, $attrs) ->

		$scope.svg = null

		# Re-render tree whenever the nodes are updated
		$scope.$on "tree.nodes.changed", (evt) ->
			$scope.render treeSrv.get()

		$scope.render = (data) ->

			unless data? then return false

			# Modify height of tree based on max depth
			# Keeps initial tree from being absurdly sized
			depth = treeSrv.getMaxDepth()
			adjustedHeight = 200 + (depth * 50)

			# Init tree data
			tree = d3.layout.tree()
				.sort(null)
				.size([900, adjustedHeight]) # sets size of tree
				.children (d) -> # defines accessor function for nodes (e.g., what the "d" object is)
					if !d.contents or d.contents.length is 0 then return null
					else return d.contents

			nodes = tree.nodes data # Setup nodes
			links = tree.links nodes # Setup links
			adjustedLinks = [] # Finalized links array that includes "special" links (loopbacks and bridges)

			angular.forEach nodes, (node, index) ->

				# If the node has any non-hierarchical links, have to process them
				# And generate new links that d3 won't create by default
				if node.hasLinkToOther

					angular.forEach node.answers, (answer, index) ->

						if answer.linkMode is "existing"

							# Grab the targeted node for the new link
							target = treeSrv.findNode treeSrv.get(), answer.target

							# Craft the new link and add source & target
							newLink = {}

							newLink.source = node
							newLink.target = target
							newLink.specialCase = "otherNode"

							links.push newLink

				# Generate "loopback" links that circle back to the same node
				# This link has the same source/target, the node itself;
				# It's just a formality really, so D3 -knows- a link exists here
				if node.hasLinkToSelf

					newLink = {}
					newLink.source = node
					newLink.target = node
					newLink.specialCase = "loopBack"

					links.push newLink


			# We need to effectively "filter" each link and create the intermediate nodes
			# The properties of the link and intermediate "bridge" nodes depends on what kind of link we have
			angular.forEach links, (link, index) ->

				# if link.specialCase is "otherNode"
				# 	source = link.source
				# 	target = link.target
				# 	intermediate =
				# 		x: source.x + (target.x - source.x)/2
				# 		y: (source.y + (target.y - source.y)/2) + 25
				# 		type: "bridge"

				# 	adjustedLinks.push {source: source, target: intermediate}, {source: intermediate, target: target}

				# else if link.specialCase is "loopBack"

				# 	intermediate =
				# 		x: link.source.x + 75
				# 		y: link.source.y + 75
				# 		type: "bridge"

				# 	adjustedLinks.push link

				# else
				source = link.source
				target = link.target
				intermediate =
					x: source.x + (target.x - source.x)/2
					y: source.y + (target.y - source.y)/2
					type: "bridge"

				# adjustedLinks.push link

				nodes.push intermediate

			# Render tree
			if $scope.svg == null
				$scope.svg = d3.select($element[0])
					.append("svg:svg")
					.attr("width", 1000) # Size of actual SVG container
					.attr("height",700) # Size of actual SVG container
					.append("svg:g")
					.attr("class", "container")
					.attr("transform", "translate(0,50)") # translates position of overall tree in svg container
			else
				$scope.svg.selectAll("*").remove()

			# Since we're using svg.line() instead of diagonal(), the links must be wrapped in a helper function
			# Hashtag justd3things
			link = d3.svg.line()
				.x( (point) ->
					point.lx
				)
				.y( (point) ->
					point.ly
				)

			# Creates special lx, ly properties so svg.line() knows what to do
			lineData = (d) ->
				points = [
					{lx: d.source.x, ly: d.source.y},
					{lx: d.target.x, ly: d.target.y}
				]

				link(points)

			# link = d3.svg.diagonal (d) ->
			# 	return [d.x, d.y]

			# Define the arrow markers that will be added to the end vertex of each link path
			$scope.svg.append("defs").append("marker")
				.attr("id", "arrowhead")
				.attr("refX", 10 + 20)
				.attr("refY", 5)
				.attr("markerWidth", 10)
				.attr("markerHeight", 10)
				.attr("orient", "auto")
				.append("path")
					.attr("d","M 0,0 L 0,10 L 10,5 Z")


			linkGroup = $scope.svg.selectAll("path.link")
				.data(links)
				.enter()
				.append("g")

			linkGroup.append("svg:path")
				.attr("class", "link")
				.attr("marker-end", "url(#arrowhead)")
				.attr("d", lineData)

			linkGroup.append("svg:circle")
				.attr("class","loopback")
				.attr("r", 50)
				.attr("transform", (d) ->

					xOffset = d.source.x + 40
					yOffset = d.source.y + 40

					"translate(#{xOffset},#{yOffset})"
				)
				.style("display", (d) ->
					if d.specialCase == "loopBack" then return null
					else return "none"
				)

			nodeGroup = $scope.svg.selectAll("g.node")
				.data(nodes)
				.enter()
				.append("svg:g")
				# .attr("class", "node")
				.attr("class", (d) ->
					if d.type is "bridge" then return "bridge"
					else return "node #{d.type}"
				)
				.on("mouseover", (d, i) ->

					if d.type is "bridge" then return

					#  Animation effects on node mouseover
					d3.select(this).select("circle")
					.transition()
					.attr("r", 30)

					# d3.select(this).select("text")
					# .text( (d) ->
					# 	d.name + " (Click to Edit)"
					# )
					# .transition()
					# .attr("x", 10)
				)
				.on("mouseout", (d, i) ->

					if d.type is "bridge" then return

					# Animation effects on node mouseout
					d3.select(this).select("circle")
					.transition()
					.attr("r", 20)

					d3.select(this).select("text")
					.text( (d) ->
						d.name
					)
					# .transition()
					# .attr("x", 0)
				)
				.on("click", (d, i) ->
					$scope.onClick {data: d} # when clicked, we return all of the node's data
				)
				.attr("transform", (d) ->
					"translate(#{d.x},#{d.y})"
				)

			nodeGroup.append("svg:circle")
				.attr("class", "node-dot")
				.attr("r", (d) ->
					return 20 # sets size of node bubbles
					# if d.type is "bridge" then return 20
					# else return 20
				)

			nodeGroup.append("svg:rect")
				.attr("width", (d) ->
					if d.name then return 10 * d.name.length
					else return 0
				)
				.attr("height", 16)
				.attr("x", -10)
				.attr("y", -8)

			nodeGroup.append("svg:text")
				.attr("text-anchor", (d) ->
					return "start" # sets horizontal alignment of text anchor
					# if d.children then return "end"
					# else return "start"
				)
				.attr("dx", (d) ->
					if d.name
						if d.name.length > 1 then return -10
						else return -5
					else return 0
				)

				# sets X label offset from node (negative left, positive right side)
				# .attr("dx", (d) ->
				# 	# if d.children then return -gap
				# 	# else return gap
				# )

				.attr("dy", 5) # sets Y label offset from node
				.attr("font-family", "Lato")
				.attr("font-size", 16)
				.text (d) ->
					d.name

		$scope.render treeSrv.get()

# Directive for the node modal dialog (add child, delete node, etc)
Adventure.directive "nodeToolsDialog", (treeSrv) ->
	restrict: "E",
	link: ($scope, $element, $attrs) ->
		# When target for the dialog changes, update the position values based on where the new node is
		$scope.$watch "nodeTools.target", (newVals, oldVals) ->

			xOffset = $scope.nodeTools.x + 10
			yOffset = $scope.nodeTools.y + 70

			styles = "left: " + xOffset + "px; top: " + yOffset + "px"

			$attrs.$set "style", styles

		$scope.copyNode = () ->
			console.log "Copying NYI!"

		$scope.dropNode = () ->
			treeSrv.findAndRemove $scope.treeData, $scope.nodeTools.target
			$scope.nodeTools.show = false
			treeSrv.set $scope.treeData
			$scope.toast "Node " + $scope.nodeTools.target + " has been removed."


Adventure.directive "nodeCreationSelectionDialog", (treeSrv) ->
	restrict: "E",
	link: ($scope, $element, $attrs) ->
		$scope.showDialog = false

		$scope.editNode = () ->
			# We need the target's node type, so grab it
			targetId = $scope.nodeTools.target
			target = treeSrv.findNode $scope.treeData, targetId

			# if node is blank, launch the node type selection. Otherwise, go right to the editor for that type
			if target.type isnt $scope.BLANK
				$scope.displayNodeCreation = target.type
			else
				$scope.showCreationDialog = true

			$scope.showBackgroundCover = true

Adventure.directive "newNodeManagerDialog", (treeSrv, $document) ->
	restrict: "E",
	link: ($scope, $element, $attrs) ->

		# Watch the newNodeManager target and kick off associated logic when it updates
		# Similar in functionality to the nodeTools dialog
		$scope.$watch "newNodeManager.target", (newVal, oldVal) ->
			if newVal isnt null
				$scope.newNodeManager.show = true

				xOffset = $scope.newNodeManager.x - 205
				yOffset = $scope.newNodeManager.y - 10

				styles =  "left: " + xOffset + "px; top: " + yOffset + "px"

				$attrs.$set "style", styles

		$scope.selectLinkMode = (mode) ->

			answer = {}

			# Grab the answer object that corresponds with the nodeManager's current target
			i = 0
			while i < $scope.answers.length
				if $scope.answers[i].target is $scope.newNodeManager.target then break
				else i++


			# Compare the prior link mode to the new one and deal with the changes
			if mode != $scope.newNodeManager.linkMode
				switch mode
					when "new"

						## HANDLE PRIOR LINK MODE: SELF
						if $scope.answers[i].linkMode is $scope.SELF

							if $scope.editedNode.hasLinkToSelf
								delete $scope.editedNode.hasLinkToSelf

						## HANDLE PRIOR LINK MODE: EXISTING
						else if $scope.answers[i].linkMode is $scope.EXISTING

							if $scope.editedNode.hasLinkToOther
								delete $scope.editedNode.hasLinkToOther


						# Create new node and update the answer's target
						targetId = $scope.addNode $scope.editedNode.id, $scope.BLANK
						$scope.answers[i].target = targetId

						# Set updated linkMode flags
						$scope.newNodeManager.linkMode = $scope.NEW
						$scope.answers[i].linkMode = $scope.NEW
						console.log "New mode selected: NEW"

						$scope.newNodeManager.target = null

					when "existing"

						# Suspend the node creation screen so the user can select an existing node
						$scope.showBackgroundCover = false
						$scope.nodeTools.show = false
						$scope.displayNodeCreation = "suspended"

						# Set the node selection mode so click events are handled differently than normal
						$scope.existingNodeSelectionMode = true

						$scope.toast "Select the point this answer should link to.", false

						# All tasks are on hold until the user selects a node to link to
						# Wait for the node to be selected
						deregister = $scope.$watch "existingNodeSelected", (newVal, oldVal) ->

							if newVal

								$scope.hideToast()

								# Set the answer's new target to the newly selected node
								$scope.answers[i].target = newVal.id

								## HANDLE PRIOR LINK MODE: NEW
								if $scope.answers[i].linkMode is $scope.NEW

									# Scrub the existing child node associated with this answer
									childNode = treeSrv.findNode $scope.treeData, $scope.newNodeManager.target
									if childNode then treeSrv.findAndRemove $scope.treeData, childNode.id

								## HANDLE PRIOR LINK MODE: SELF
								if $scope.answers[i].linkMode is $scope.SELF

									if $scope.editedNode.hasLinkToSelf
										delete $scope.editedNode.hasLinkToSelf

								# Set updated linkMode flags and redraw tree
								$scope.editedNode.hasLinkToOther = true
								$scope.answers[i].linkMode = $scope.EXISTING

								treeSrv.set $scope.treeData

								# $scope.newNodeManager.linkMode = $scope.EXISTING
								console.log "New mode selected: EXISTING"

								# Deregister the watch listener now that it's not needed
								deregister()

								$scope.existingNodeSelected = null
								$scope.newNodeManager.target = null
								$scope.displayNodeCreation = "none" # displayNodeCreation should be updated from "suspended"


					when "self"

						# Set answer row's target to the node being edited
						$scope.answers[i].target = $scope.editedNode.id

						## HANDLE PRIOR LINK MODE: NEW
						if $scope.answers[i].linkMode is $scope.NEW

							# Scrub the existing child node associated with this answer
							childNode = treeSrv.findNode $scope.treeData, $scope.newNodeManager.target
							treeSrv.findAndRemove $scope.treeData, childNode.id

						## HANDLE PRIOR LINK MODE: EXISTING
						else if $scope.answers[i].linkMode is $scope.EXISTING

							if $scope.editedNode.hasLinkToOther
								delete $scope.editedNode.hasLinkToOther

						# Set updated linkMode flags and redraw the tree
						$scope.editedNode.hasLinkToSelf = true
						$scope.answers[i].linkMode = $scope.SELF

						treeSrv.set $scope.treeData

						$scope.newNodeManager.linkMode = $scope.SELF
						console.log "New mode selected: SELF"

						$scope.newNodeManager.target = null

			$scope.newNodeManager.show = false

Adventure.directive "nodeCreation", (treeSrv) ->
	restrict: "E",
	link: ($scope, $element, $attrs) ->

		$scope.$on "editedNode.target.changed", (evt) ->

			console.log "editedNode updated! Type is now: " + $scope.editedNode.type

			if $scope.editedNode
				# Initialize the node edit screen with the node's info. If info doesn't exist yet, init properties
				if $scope.editedNode.question then $scope.question = $scope.editedNode.question

				if $scope.editedNode.answers then $scope.answers = $scope.editedNode.answers
				else
					$scope.answers = []
					$scope.newAnswer()


		# Update the node's properties when the associated input models change
		$scope.$watch "question", (newVal, oldVal) ->
			if newVal
				$scope.editedNode.question = newVal

		$scope.$watch "answers", ((newVal, oldVal) ->
			if newVal
				$scope.editedNode.answers = $scope.answers
		), true

		$scope.newAnswer = () ->

			# We create the new node first, so we can grab the new node's generated id
			targetId = $scope.addNode $scope.editedNode.id, $scope.BLANK

			newAnswer =
				text: null
				feedback: null
				target: targetId
				linkMode: $scope.NEW

			# Add a matches property to the answer object if it's a short answer question.
			if $scope.editedNode.type is $scope.SHORTANS
				newAnswer.matches = []

			$scope.answers.push newAnswer

		$scope.removeAnswer = (index) ->

			# Grab node id of answer node to be removed
			targetId = $scope.answers[index].target

			# Remove it from answers array
			$scope.answers.splice index, 1

			# Remove the node from the tree
			treeSrv.findAndRemove treeSrv.get(), targetId
			treeSrv.set $scope.treeData

			# If the node manager modal is open for this answer, close it
			if targetId is $scope.newNodeManager.target
				$scope.newNodeManager.show = false
				$scope.newNodeManager.target = null

		$scope.manageNewNode = ($event, target, mode) ->
			$scope.newNodeManager.x = $event.currentTarget.getBoundingClientRect().left
			$scope.newNodeManager.y = $event.currentTarget.getBoundingClientRect().top
			$scope.newNodeManager.linkMode = mode
			$scope.newNodeManager.target = target

# Directive for each short answer set. Contains logic for adding and removing individual answer matches.
Adventure.directive "shortAnswerSet", (treeSrv) ->
	restrict: "A",
	link: ($scope, $element, $attrs) ->

		$scope.addAnswerMatch = (index) ->

			# Don't do anything if there isn't anything actually submitted
			unless $scope.newMatch.length then return

			# first check to see if the entry already exists
			i = 0

			unless $scope.answers[index].matches.length
				$scope.answers[index].matches.push $scope.newMatch
				$scope.newMatch = ""
				return

			while i < $scope.answers[index].matches.length

				matchTo = $scope.answers[index].matches[i].toLowerCase()

				if matchTo.localeCompare($scope.newMatch.toLowerCase()) is 0
					$scope.toast "This match already exists!"
					return

				i++

			$scope.answers[index].matches.push $scope.newMatch
			$scope.newMatch = ""

		$scope.removeAnswerMatch = (matchIndex, answerIndex) ->

			$scope.answers[answerIndex].matches.splice matchIndex, 1


