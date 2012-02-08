
expect = require('chai').expect
fs = require('fs')
_ = require('underscore')

long_delay = (func) -> setTimeout func, 1000
delay = _.defer #(func) -> setTimeout func, 100

appendSync = (filename, str) ->
  len = fs.statSync(filename).size
  fd = fs.openSync(filename, 'a')
  fs.writeSync(fd, str, len)
  fs.closeSync(fd)

describe 'text-file-follower', ->

  before ->
    try
      fs.mkdirSync('fixtures')

  describe '#load-module', ->

    it 'should load when required', ->
      expect(require('../lib')).to.be.ok

  follower_debug = require('../lib').__get_debug_exports()

  describe '#deduce_newline_value', ->

    it 'should be okay with an empty string', ->
      empty_string = ''
      expect(follower_debug.deduce_newline_value(empty_string)).to.be.ok

    it 'should be correct with a string that is just a newline', ->
      newline = '\n'
      expect(follower_debug.deduce_newline_value(newline)).to.equal(newline)
      newline = '\r\n'
      expect(follower_debug.deduce_newline_value(newline)).to.equal(newline)

    it 'should default to unix-style if there are no newlines', ->
      no_newlines = 'foobar'
      expect(follower_debug.deduce_newline_value(no_newlines)).to.equal('\n')

    it 'should correctly deduce Windows-style newlines', ->
      windows_newlines = 'foo\r\nbar'
      expect(follower_debug.deduce_newline_value(windows_newlines)).to.equal('\r\n')

    it 'should correctly deduce unix-style newlines', ->
      windows_newlines = 'foo\nbar'
      expect(follower_debug.deduce_newline_value(windows_newlines)).to.equal('\n')

  describe '#get_lines', ->

    it 'should be okay with an empty string', ->
      empty_string = ''
      expect(follower_debug.get_lines(empty_string)).to.be.ok

    it "should return zero and an empty array if there is no newline", ->
      no_newlines = 'foobar'
      expect(follower_debug.get_lines(no_newlines)).to.eql([0, []])

    it "should correctly split empty lines", ->
      only_newlines = '\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['']])

      only_newlines = '\r\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['']])

      only_newlines = '\n\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['', '']])

      only_newlines = '\r\n\r\n'
      expect(follower_debug.get_lines(only_newlines)).to.eql([only_newlines.length, ['', '']])

    it "should correctly split input that ends with a newline", ->

      newline_end = "foobar\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foobar']])

      newline_end = "foobar\r\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foobar']])

      newline_end = "foo\nbar\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foo', 'bar']])

      newline_end = "foo\r\nbar\r\n"
      result = follower_debug.get_lines(newline_end)
      expect(result).to.eql([newline_end.length, ['foo', 'bar']])

    it "should correctly split input that does not end with a newline", ->

      # A line isn't considered complete, and so shouldn't be counted, if it 
      # doesn't end with a newline.

      not_newline_end = "foobar"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql([0, []])

      not_newline_end = "foo\nbar"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\n'.length, ['foo']])

      not_newline_end = "foo\r\nbar"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\r\n'.length, ['foo']])

      not_newline_end = "foo\nbar\nasdf"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\nbar\n'.length, ['foo', 'bar']])

      not_newline_end = "foo\r\nbar\r\nasdf"
      result = follower_debug.get_lines(not_newline_end)
      expect(result).to.eql(['foo\r\nbar\r\n'.length, ['foo', 'bar']])

  describe '#follow', ->

    before ->
      try
        fs.mkdirSync('fixtures/testdir')
      fs.writeFileSync('fixtures/a.test', '')
      fs.writeFileSync('fixtures/b.test', '')
    
    beforeEach ->
      # Make it zero-size again
      fs.writeFileSync('fixtures/a.test', '')
    
    follower = require('../lib')

    it "should reject bad arguments", ->
      # no args
      expect(-> follower.follow()).to.throw(TypeError)
      # filename not a string
      expect(-> follower.follow(123, {}, ->)).to.throw(TypeError)
      # options not an object
      expect(-> follower.follow('foobar', 123, ->)).to.throw(TypeError)
      # listener not a function
      expect(-> follower.follow('foobar', {}, 123)).to.throw(TypeError)
      # if two args, second arg is neither an object (options) nor a function (listener)
      expect(-> follower.follow('foobar', 123)).to.throw(TypeError)

    it "should throw an error when given something that isn't a file", ->
      expect(-> follower.follow('fixtures/testdir')).to.throw(Error)

    it "should throw an error when the file doesn't exist", ->
      expect(-> follower.follow('foobar')).to.throw(Error)

    it "should start successfully in a simple scenario", (done) ->
      f = follower.follow('fixtures/a.test')
      expect(f).to.be.ok
      f.close()
      done()

    it "should read lines from a fresh file successfully, using the emitter", (done) ->
      line_count = 0
      next = null

      f = follower.follow('fixtures/a.test')
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()

      received_lines = []
      f.on 'line', (filename, line) -> 
        line_count++
        expect(filename).to.equal('fixtures/a.test')
        received_lines.push(line)
        delay next

      _.defer ->
        # no newline
        appendSync('fixtures/a.test', 'abc')
        delay ->
          expect(line_count).to.equal(0)

          appendSync('fixtures/a.test', '\n')
          next = -> 
            expect(line_count).to.equal(1)
            expect(received_lines.shift()).to.equal('abc')

            appendSync('fixtures/a.test', 'def\n')
            next = -> 
              expect(line_count).to.equal(2)
              expect(received_lines.shift()).to.equal('def')

              call_count = 0
              appendSync('fixtures/a.test', 'ghi\njkl\n')
              next = -> 
                # This will get called twice.
                if call_count == 0
                  expect(received_lines.shift()).to.equal('ghi')
                  call_count = 1
                else if call_count == 1
                  expect(received_lines.shift()).to.equal('jkl')

                  # Finished
                  f.close()
                  done()
                else
                  throw Error('bad line_count')

    it "should read lines from a fresh file successfully, using the listener callback", (done) ->
      line_count = 0
      next = null
      received_lines = []

      listener = (filename, line) -> 
        line_count++
        expect(filename).to.equal('fixtures/a.test')
        received_lines.push(line)
        delay next

      f = follower.follow('fixtures/a.test', listener)
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()


      _.defer ->
        appendSync('fixtures/a.test', 'abc\n')
        next = -> 
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          appendSync('fixtures/a.test', 'def\n')
          next = -> 
            expect(line_count).to.equal(2)
            expect(received_lines.shift()).to.equal('def')

            f.close()
            done()

    it "should read lines from the end of a non-empty file", (done) ->
      line_count = 0
      next = null
      received_lines = []

      listener = (filename, line) -> 
        line_count++
        expect(filename).to.equal('fixtures/a.test')
        received_lines.push(line)
        delay next

      appendSync('fixtures/a.test', 'will not\nget read\n')

      f = follower.follow('fixtures/a.test', listener)
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()

      _.defer ->
        appendSync('fixtures/a.test', 'abc\n')
        next = -> 
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          appendSync('fixtures/a.test', 'def\n')
          next = -> 
            expect(line_count).to.equal(2)
            expect(received_lines.shift()).to.equal('def')

            f.close()
            done()

    it "should successfully work with two different files at once", (done) ->
      line_count = 0

      long_delay ->

        f1_line = 'f1'
        f1_filename = 'fixtures/a.test'
        f1 = follower.follow(f1_filename)
        f1.on 'error', -> throw new Error()
        f1.on 'line', (filename, line) ->
          expect(filename).to.equal(f1_filename)
          expect(line).to.equal(f1_line)
          line_count++

        f2_line = 'f2'
        f2_filename = 'fixtures/b.test'
        f2 = follower.follow(f2_filename)
        f2.on 'error', -> throw new Error()
        f2.on 'line', (filename, line) ->
          expect(filename).to.equal(f2_filename)
          expect(line).to.equal(f2_line)
          line_count++

        f1.on 'success', ->
          appendSync(f1_filename, f1_line+'\n')

        f2.on 'success', ->
          appendSync(f2_filename, f2_line+'\n')

        long_delay ->
          expect(line_count).to.equal(2)
          f1.close()
          f2.close()
          done()

    it "should successfully close and re-open a follower", (done) ->
      line_count = 0
      next = null
      curr_filename = ''

      listener = (filename, line) -> 
        console.log('LLL')
        line_count++
        expect(filename).to.equal(curr_filename)
        received_lines.push(line)
        delay next

      console.log('yyy')
      curr_filename = 'fixtures/a.test'
      f = follower.follow(curr_filename)
      expect(f).to.be.ok
      f.on 'error', -> throw new Error()
      f.on 'line', listener
      console.log('zzz')

      received_lines = []
      _.defer ->
        appendSync(curr_filename, 'abc\n')
        console.log('aaa')
        next = -> 
          console.log('bbb')
          expect(line_count).to.equal(1)
          expect(received_lines.shift()).to.equal('abc')

          # Close
          f.close()

          # Re-open
          line_count = 0
          curr_filename = 'fixtures/b.test'
          f = follower.follow(curr_filename)
          expect(f).to.be.ok
          f.on 'error', -> throw new Error()
          f.on 'line', listener

          appendSync(curr_filename, 'def\n')
          console.log('ccc')
          next = -> 
            console.log('ddd')
            expect(line_count).to.equal(1)
            expect(received_lines.shift()).to.equal('def')

            f.close()
            delay ->
              done()


      
