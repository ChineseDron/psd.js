class PSDLayer
  CHANNEL_SUFFIXES =
    '-2': 'layer mask'
    '-1': 'A'
    0: 'R'
    1: 'G'
    2: 'B'
    3: 'RGB'
    4: 'CMYK'
    5: 'HSL'
    6: 'HSB'
    9: 'Lab'
    11: 'RGB'
    12: 'Lab'
    13: 'CMYK'

  SECTION_DIVIDER_TYPES =
    0: "other"
    1: "open folder"
    2: "closed folder"
    3: "bounding section divider"

  COMPRESSIONS =
    0: 'Raw'
    1: 'RLE'
    2: 'ZIP'
    3: 'ZIPPrediction'

  BLEND_MODES =
    "norm": "normal"
    "dark": "darken"
    "lite": "lighten"
    "hue":  "hue"
    "sat":  "saturation"
    "colr": "color"
    "lum":  "luminosity"
    "mul":  "multiply"
    "scrn": "screen"
    "diss": "dissolve"
    "over": "overlay"
    "hLit": "hard light"
    "sLit": "soft light"
    "diff": "difference"
    "smud": "exclusion"
    "div":  "color dodge"
    "idiv": "color burn"
    "lbrn": "linear burn"
    "lddg": "linear dodge"
    "vLit": "vivid light"
    "lLit": "linear light"
    "pLit": "pin light"
    "hMix": "hard mix"

  SAFE_FONTS = [
    "Arial"
    "Courier New"
    "Georgia"
    "Times New Roman"
    "Verdana"
    "Trebuchet MS"
    "Lucida Sans"
    "Tahoma"
  ]

  constructor: (@file, @baseLayer = false, @header = null) ->
    @images = []
    @mask = {}

  parse: (layerIndex = null) ->
    return @parseBaseLayer() if @baseLayer

    @parseInfo(layerIndex)
    @parseBlendModes()

    # remember position for skipping unrecognized data
    [extralen] = @file.readf ">L"
    extrastart = @file.tell()

    @parseMaskData()

    while @file.pos - extrastart < extralen
      [signature, key, size] = @file.readf ">4s4s4s"

      prevPos = @file.tell()

      switch key
        # Layer ID
        when "lyid" then @id = @file.readUInt16()

        # Metadata setting
        when "shmd" then @readMetadata()

        # Section divider setting
        when "lsct" then @readLayerSectionDivider()

        # Unicode name
        when "luni"
          @name = @file.readUnicodeString()
          Log.debug "Layer name: #{@name}"

        # Vector mask
        when "vmsk" then @readVectorMask()

        # Type tool
        when "TySh" then @readTypeTool()

    # Skip extra data
    @file.seek extrastart + extralen, false

  parseBaseLayer: ->
    height = @header.height
    width = @header.width
    @top = 0
    @left = 0
    @bottom = height
    @right = width
    @width = width
    @height = height

    channels = @header.channels
    chanDelta = 3 - channels
    @channelsInfo = []
    @channelsInfo.push([i, 0]) for i in [chanDelta...channels+chanDelta]

    @blendMode =
      code: "norm"
      label: "normal"

    @opacity = 255
    @visible = true
    @name = "Canvas"
    @layerId = 0


  parseInfo: (layerIndex) ->
    @idx = layerIndex

    ###
    Layer Info
    ###
    [@top, @left, @bottom, @right, @channels] = @file.readf ">LLLLH"
    [@rows, @cols] = [@bottom - @top, @right - @left]

    Log.debug "Layer #{@idx}:", @

    # Sanity check
    if @bottom < @top or @right < @left or @channels > 64
      Log.debug "Somethings not right, attempting to skip layer."
      @file.seek 6 * @channels + 12
      @file.skipBlock "layer info: extra data"
      return # next layer

    # Read channel info
    @channelsInfo = []
    for i in [0...@channels]
      [channelID, channelLength] = @file.readf ">hL"
      Log.debug "Channel #{i}: id=#{channelID}, #{channelLength} bytes, type=#{CHANNEL_SUFFIXES[channelID]}"

      @channelsInfo.push [channelID, channelLength]

  parseBlendModes: ->
    @blendMode = {}

    [
      @blendMode.sig, 
      @blendMode.key, 
      @blendMode.opacity, 
      @blendMode.clipping, 
      @blendMode.flags, 
      @blendMode.filler
    ] = @file.readf ">4s4sBBBB"

    @blendMode.key = @blendMode.key.trim()
    @blendMode.opacp = (@blendMode.opacity * 100 + 127) / 255
    @blendMode.blending = BLEND_MODES[@blendMode.key]

    Log.debug "Blending mode:", @blendMode

  parseMaskData: ->
    [@mask.size] = @file.readf ">L"
    if @mask.size
      [@mask.top, @mask.left, @mask.bottom, @mask.right, @mask.defaultColor, @mask.flags] = @file.readf ">LLLLBB"

      # skip remainder
      @file.seek @mask.size - 18
      [@mask.rows, @mask.cols] = [@mask.bottom - @mask.top, @mask.right - @mask.left]

    @file.skipBlock "layer blending ranges"

  readMetadata: ->
    Log.debug "Parsing layer metadata..."

    count = @file.readUInt16()

    for i in [0...count]
      [sig, key, padding] = @file.readf ">4s4s4s"

      #if key is "mlst"
        #readAnimation. needs research.

      @file.skipBlock("image metadata")
        
  readLayerSectionDivider: ->
    code = @file.readUInt16()
    @layerType = SECTION_DIVIDER_TYPES[code]
    
  readVectorMask: ->
    version = @file.readInt()
    flags = @file.read 4

    # TODO read path information

  readTypeTool: ->
    ver = @file.readShortInt()
    transforms = []
    transforms.push @file.readDouble() for i in [0...6]

    textVer = @file.readShortInt()
    descrVer = @file.readInt()
    return if ver isnt 1 or textVer isnt 50 or descrVer isnt 16

    textData = @file.readDescriptorStructure()

    wrapVer = @readShortInt()
    descrVer = @readInt()
    wrapData = @file.readDescriptorStructure()

    rectangle = []
    rectangle.push @file.readDouble() for i in [0...4]

    @textData = textData
    @wrapData = wrapData

    styledText = []
    psDict = @textData.EngineData.value
    text = psDict.EngineDict.Editor.Text
    styleRun = psDict.EngineDict.StyleRun
    stylesList = styleRun.RunArray
    stylesRunList = styleRun.RunLengthArray

    fontsList = psDict.DocumentResources.FontSet
    start = 0
    for own i, style of stylesList
      st = style.StyleSheet.StyleSheetData
      end = parseInt(start + stylesRunList[i], 10)
      fontI = st.Font
      fontName = fontsList[fontI].Name
      safeFontName = @getSafeFont(fontName)

      color = []
      color.push(255*j) for j in st.FillColor.Values[1..]

      lineHeight = if st.Leading is 1500 then "Auto" else st.Leading
      piece = text[start...end]
      styledText.push
        text: piece
        style:
          font: safeFontName
          size: st.FontSize
          color: Util.rgbToHex("rgb(#{color[0]}, #{color[1]}, #{color[2]})")
          underline: st.Underline
          allCaps: st.FontCaps
          italic: !!~ fontName.indexOf("Italic") or st.FauxItalic
          bold: !!~ fontName.indexOf("Bold") or st.FauxBold
          letterSpacing: st.Tracking / 20
          lineHeight: lineHeight
          paragraphEnds: piece.substr(-1) in ["\n", "\r"]

      start += stylesRunList[i]

    @styledText = styledText

  getSafeFont: (font) ->
    for safeFont in SAFE_FONTS
      it = true
      for word in safeFont.split " "
        it = false if not !!~ font.indexOf(word)

      return safeFont if it

    font

  getImageData: (readPlaneInfo = true, lineLengths = []) ->
    @channels =
      a: []
      r: []
      g: []
      b: []

    opacityDivider = @opacity / 255

    for own i, channelTuple of @channelsInfo
      [channelId, length] = channelTuple
      if channelId < -1
        width = @mask.cols
        height = @mask.rows
      else
        width = @cols
        height = @rows

      channel = @readColorPlane readPlaneInfo, lineLengths, i, height, width
      switch channelId
        when -1
          @channels.a = []
          @channels.a.push (ch * opacityDivider) for ch in channel
        when 0 then @channels.r = channel
        when 1 then @channels.g = channel
        when 2 then @channels.b = channel
        else
          result = []
          for i in [0...channel.length]
            result.push @channels.a[i] * (channel[i]/255)

          @channels.a = result

    @makeImage()

  readColorPlane: (readPlaneInfo, lineLengths, planeNum, height, width) ->
    size = width * height
    imageData = []
    rleEncoded = false

    if readPlaneInfo
      compression = @file.readShortInt()
      Log.debug "Compression: id=#{compression}, name=#{COMPRESSIONS[compression]}"

      rleEncoded = compression is 1
      if rleEncoded
        if not lineLengths
          lineLengths = []
          lineLengths.push @file.readShortInt() for a in [0...height]
      else
        Log.debug "ERROR: compression not implemented yet. Skipping."

      planeNum = 0
    else
      rleEncoded = lineLengths.length isnt 0

    if rleEncoded
      imageData = @readPlaneCompressed lineLengths, planeNum, height, width
    else
      imageData = @file.readBytesList(size)

    imageData

  readPlaneCompressed: (lineLengths, planeNum, height, width) ->
    b = []
    b.push 0 for x in [0...(width*height)]
    s = []
    pos = 0
    lineIndex = planeNum * height

    for i in [0...height]
      len = lineLengths[lineIndex]
      lineIndex++
      s = @file.readBytesList(len)
      @decodeRLE s, 0, len, b, pos
      pos += width

    b

  decodeRLE: (src, sindex, slen, dst, dindex) ->
    max = sindex + slen

    while sindex < max
      b = src[sindex]
      sindex++
      n = b
      if b > 127
        n = 255 - n + 2
        b = src[sindex]
        sindex++
        for i in [0...n]
          dst[dindex] = b
          dindex++
      else
        n++
        dst[dindex...dindex+n] = src[sindex...sindex+n]
        dindex += n
        sindex += n

  makeImage: ->
    return if not @cols? or not @rows?

    type = if isNaN(@channels.a[0]) then "RGB" else "RGBA"
    image = new PSDImage(type, @cols, @rows, @channels)
    
    Log.debug "Image: type=#{type}, width=#{@cols}, height=#{@rows}"

    @images.push image