//
//  Operations.swift
//  HSTracker
//
//  Created by AO on 2.01.22.
//  Copyright © 2022 Benjamin Michotte. All rights reserved.
//

import Foundation

extension OperationQueue {
    class func serialOpertaionQueue() -> OperationQueue {
        let queue = OperationQueue()
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
//        serialQueue = DispatchQueue(label: "com.bot.queue")
//        queue.underlyingQueue = serialQueue
        return queue
    }
    
    func addBlock(_ block: BlockOperation) {
//        addOperation(block)
//        block.completionBlock = {
//            self.progress.totalUnitCount -= 1
//            self.progress.totalUnitCount = max(self.progress.totalUnitCount, 0)
//        }
//        progress.totalUnitCount += 1
        waitAndAddBlock(block)
    }
    
    func addBlock(_ exCode: @escaping (()->Void)) {
//        let block = BlockOperation()
//        block.addExecutionBlock(exCode)
//        addOperation(block)
//        block.completionBlock = {
//            self.progress.totalUnitCount -= 1
//            self.progress.totalUnitCount = max(self.progress.totalUnitCount, 0)
//        }
//        progress.totalUnitCount += 1
        waitAndAddBlock(exCode)
    }
    
    func waitAndAddBlock(_ block: BlockOperation) {
        addBarrierBlock {
//            self.cancel()
            self.addOperation(block)
            block.completionBlock = {
                self.progress.totalUnitCount -= 1
                self.progress.totalUnitCount = max(self.progress.totalUnitCount, 0)
            }
            self.progress.totalUnitCount += 1
        }
    }
    
    func waitAndAddBlock(_ exCode: @escaping (()->Void)) {
        addBarrierBlock {
//            self.cancel()
            let block = BlockOperation()
            block.addExecutionBlock(exCode)
            self.addOperation(block)
            block.completionBlock = {
                self.progress.totalUnitCount -= 1
                self.progress.totalUnitCount = max(self.progress.totalUnitCount, 0)
            }
            self.progress.totalUnitCount += 1
        }
    }
    
    func cancel() {
        cancelAllOperations()
        progress.totalUnitCount = 0
        progress.completedUnitCount = 0
    }
    
    var isFinished: Bool {
        return progress.totalUnitCount == 0 || progress.isFinished
    }
}


extension Operation {
    class func blockWithSema(execBloc: @escaping ((DispatchSemaphore)->Void)) -> BlockOperation {
        let op = BlockOperation()
        op.addExecutionBlock { [weak op] in
            let sem = DispatchSemaphore(value: 0)
                if op?.isCancelled == true {
                    log("cancels")
                    sem.signal()
                    execBloc(sem)
                    return
                }
                execBloc(sem)
                sem.wait()
        }
        return op
    }
    
    class func delay(_ time: TimeInterval) -> BlockOperation {
//        return blockWithSema { sem in
//            DispatchQueue.global().asyncAfter(deadline: .now() + time) {
//                sem.signal()
//            }
//        }
        return BlockOperation {
            usleep(useconds_t(time * 1000_000))
        }
    }
    
    class func click(_ position: NSPoint) -> BlockOperation {
        return blockWithSema { sem in
            CGEvent.letfClick(position: position) {
                sem.signal()
            }
        }
    }
    
    class func scroll(top: Bool = true) -> BlockOperation {
        blockWithSema { sem in
            CGEvent.scroll(top: top) {
                sem.signal()
            }
        }
    }
    
    class func cancel() -> BlockOperation {
        return BlockOperation {
            AppDelegate.instance().botFnc.operationQueue.cancel()
        }
    }
    
    class func move(position: NSPoint) -> BlockOperation {
        return blockWithSema { sem in
            CGEvent.move(position: position) {
                sem.signal()
            }
        }
    }
    
    class func detectCircles(completion: @escaping ImageRecognitionHelper.mlCompletion) -> BlockOperation {
        return blockWithSema { sem in
            ImageRecognitionHelper.DetecktMapCircles() { strings in
                sem.signal()
                completion(strings)
            }
        }
    }
    
    class func analizeMap(bot: BotFnc) -> BlockOperation {
        return blockWithSema { sem in
            bot.analyzeMap {
                sem.signal()
            }
        }
    }
}
